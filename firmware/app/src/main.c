#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include "audio_capture.h"
#include "ble_service.h"
#include "buttons.h"
#include "haptics.h"
#include "lcd_driver.h"
#include "power.h"
#include "watch_protocol.h"

LOG_MODULE_REGISTER(main, LOG_LEVEL_INF);

static void on_call_state(enum watch_call_state state, const char *caller_name)
{
	ARG_UNUSED(caller_name);

	buttons_set_call_state(state);

	if (state == WATCH_CALL_STATE_INCOMING) {
		haptics_alarm(true, true);
		lcd_driver_set_alarm_icon(true);
	} else {
		haptics_stop();
		lcd_driver_set_alarm_icon(false);
	}
	lcd_driver_flush();
}

static void on_time_sync(const struct watch_time_sync_payload *sync)
{
	power_apply_time_sync(sync);
}

static void on_temperature(const struct watch_temperature_payload *temp)
{
	power_apply_temperature(temp);
}

int main(void)
{
	LOG_INF("CasioAI watch firmware starting");

	struct ble_service_callbacks callbacks = {
		.on_call_state = on_call_state,
		.on_time_sync = on_time_sync,
		.on_temperature = on_temperature,
		.on_session_mode = NULL, /* ble_service applies it internally already */
	};

	int err;

	err = ble_service_init(&callbacks);
	if (err) {
		LOG_ERR("ble_service_init failed (%d)", err);
		return err;
	}

	err = lcd_driver_init();
	if (err) {
		LOG_ERR("lcd_driver_init failed (%d)", err);
		/* Keep going — BLE/buttons still work even if the display doesn't. */
	}

	err = haptics_init();
	if (err) {
		LOG_ERR("haptics_init failed (%d)", err);
	}

	err = buttons_init();
	if (err) {
		LOG_ERR("buttons_init failed (%d)", err);
	}

	err = power_init();
	if (err) {
		LOG_ERR("power_init failed (%d)", err);
	}

	err = ble_service_start_advertising();
	if (err) {
		LOG_ERR("Advertising failed to start (%d)", err);
		return err;
	}

	LOG_INF("Advertising as \"%s\"", CONFIG_BT_DEVICE_NAME);
	return 0;
}
