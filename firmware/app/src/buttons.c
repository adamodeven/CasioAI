/*
 * Four physical buttons, remapped from their stock Casio functions — see
 * PINMAP.md#button-remapping for the reasoning. GPIO interrupts only
 * timestamp/queue work; actual handling (BLE notify calls, session mode
 * changes) happens in workqueue context, never in the ISR itself.
 */
#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include "audio_capture.h"
#include "ble_service.h"
#include "buttons.h"

LOG_MODULE_REGISTER(buttons, LOG_LEVEL_INF);

#define MUSIC_LONG_PRESS_MS   600
#define MUSIC_DOUBLE_PRESS_MS 400

static const struct gpio_dt_spec talk_btn = GPIO_DT_SPEC_GET(DT_ALIAS(talk_button), gpios);
static const struct gpio_dt_spec light_btn = GPIO_DT_SPEC_GET(DT_ALIAS(light_button), gpios);
static const struct gpio_dt_spec music_btn = GPIO_DT_SPEC_GET(DT_ALIAS(music_button), gpios);
static const struct gpio_dt_spec capture_btn = GPIO_DT_SPEC_GET(DT_ALIAS(capture_button), gpios);

static struct gpio_callback talk_cb_data;
static struct gpio_callback light_cb_data;
static struct gpio_callback music_cb_data;
static struct gpio_callback capture_cb_data;

static struct k_work_delayable talk_work;
static struct k_work_delayable capture_work;
static struct k_work_delayable music_long_press_work;
static struct k_work_delayable music_double_press_work;

static enum watch_call_state call_state = WATCH_CALL_STATE_IDLE;

static bool music_long_press_fired;
static int64_t music_last_release_ms;

void buttons_set_call_state(enum watch_call_state state)
{
	call_state = state;
}

/* ---- Talk button (top-right) ---- */

static void talk_work_handler(struct k_work *work)
{
	bool pressed = gpio_pin_get_dt(&talk_btn) > 0;

	if (call_state == WATCH_CALL_STATE_INCOMING) {
		if (pressed) {
			ble_service_notify_call_command(WATCH_CALL_CMD_ANSWER);
		}
		return;
	}

	if (pressed) {
		ble_service_apply_session_mode(WATCH_SESSION_ACTIVE);
		ble_service_notify_button_event(WATCH_BUTTON_TALK_START);
		audio_capture_start();
	} else {
		audio_capture_stop();
		ble_service_notify_button_event(WATCH_BUTTON_TALK_END);
		ble_service_apply_session_mode(WATCH_SESSION_IDLE);
	}
}

static void talk_isr(const struct device *dev, struct gpio_callback *cb, uint32_t pins)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(cb);
	ARG_UNUSED(pins);
	k_work_schedule(&talk_work, K_MSEC(20)); /* debounce */
}

/* ---- Capture button (bottom-right) ---- */

static void capture_work_handler(struct k_work *work)
{
	bool pressed = gpio_pin_get_dt(&capture_btn) > 0;

	if (call_state == WATCH_CALL_STATE_INCOMING) {
		if (pressed) {
			ble_service_notify_call_command(WATCH_CALL_CMD_REJECT);
		}
		return;
	}

	if (pressed) {
		ble_service_apply_session_mode(WATCH_SESSION_ACTIVE);
		ble_service_notify_button_event(WATCH_BUTTON_HOLD_START);
		audio_capture_start();
	} else {
		audio_capture_stop();
		ble_service_notify_button_event(WATCH_BUTTON_HOLD_END);
		ble_service_apply_session_mode(WATCH_SESSION_IDLE);
	}
}

static void capture_isr(const struct device *dev, struct gpio_callback *cb, uint32_t pins)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(cb);
	ARG_UNUSED(pins);
	k_work_schedule(&capture_work, K_MSEC(20));
}

/* ---- Light button (top-left) ---- */

static void light_isr(const struct device *dev, struct gpio_callback *cb, uint32_t pins)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(cb);
	ARG_UNUSED(pins);
	/* Stock A158WE has no backlight illuminator, so there's nothing to
	 * drive electrically in rev1 — this button is wired through for case
	 * compatibility. If a rev2 PCB adds an LED, drive it from here.
	 */
}

/* ---- Music button (bottom-left): short=play/pause, double=next, long=previous ---- */

static void music_long_press_handler(struct k_work *work)
{
	if (gpio_pin_get_dt(&music_btn) > 0) { /* still held */
		music_long_press_fired = true;
		ble_service_notify_music_command(WATCH_MUSIC_CMD_PREVIOUS);
	}
}

static void music_double_press_handler(struct k_work *work)
{
	/* No second press arrived within the window: it was a single tap. */
	ble_service_notify_music_command(WATCH_MUSIC_CMD_PLAY_PAUSE);
}

static void music_isr(const struct device *dev, struct gpio_callback *cb, uint32_t pins)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(cb);
	ARG_UNUSED(pins);

	bool pressed = gpio_pin_get_dt(&music_btn) > 0;

	if (pressed) {
		music_long_press_fired = false;
		k_work_schedule(&music_long_press_work, K_MSEC(MUSIC_LONG_PRESS_MS));
		return;
	}

	/* Released */
	k_work_cancel_delayable(&music_long_press_work);
	if (music_long_press_fired) {
		return; /* PREVIOUS already fired on the long-press timer */
	}

	int64_t now = k_uptime_get();
	if (music_last_release_ms != 0 && (now - music_last_release_ms) <= MUSIC_DOUBLE_PRESS_MS) {
		k_work_cancel_delayable(&music_double_press_work);
		music_last_release_ms = 0;
		ble_service_notify_music_command(WATCH_MUSIC_CMD_NEXT);
	} else {
		music_last_release_ms = now;
		k_work_schedule(&music_double_press_work, K_MSEC(MUSIC_DOUBLE_PRESS_MS));
	}
}

/* ---- Setup ---- */

static int setup_button(const struct gpio_dt_spec *btn, struct gpio_callback *cb_data,
			 gpio_callback_handler_t handler)
{
	if (!gpio_is_ready_dt(btn)) {
		LOG_ERR("Button GPIO not ready");
		return -ENODEV;
	}

	int err = gpio_pin_configure_dt(btn, GPIO_INPUT);
	if (err) {
		return err;
	}

	err = gpio_pin_interrupt_configure_dt(btn, GPIO_INT_EDGE_BOTH);
	if (err) {
		return err;
	}

	gpio_init_callback(cb_data, handler, BIT(btn->pin));
	return gpio_add_callback(btn->port, cb_data);
}

int buttons_init(void)
{
	k_work_init_delayable(&talk_work, talk_work_handler);
	k_work_init_delayable(&capture_work, capture_work_handler);
	k_work_init_delayable(&music_long_press_work, music_long_press_handler);
	k_work_init_delayable(&music_double_press_work, music_double_press_handler);

	int err;
	err = setup_button(&talk_btn, &talk_cb_data, talk_isr);
	if (err) {
		return err;
	}
	err = setup_button(&light_btn, &light_cb_data, light_isr);
	if (err) {
		return err;
	}
	err = setup_button(&music_btn, &music_cb_data, music_isr);
	if (err) {
		return err;
	}
	err = setup_button(&capture_btn, &capture_cb_data, capture_isr);
	if (err) {
		return err;
	}

	return 0;
}
