/*
 * Stock piezo buzzer (PWM tone) and vibration motor (PWM through a
 * transistor driver, not direct GPIO — see PINMAP.md) control, including
 * the alarm's vibrate/beep pattern.
 */
#include <zephyr/devicetree.h>
#include <zephyr/drivers/pwm.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include "haptics.h"

LOG_MODULE_REGISTER(haptics, LOG_LEVEL_INF);

#define ALARM_PULSE_ON_MS  500
#define ALARM_PULSE_OFF_MS 500
#define ALARM_TIMEOUT_MS   (60 * 1000) /* auto-stop if nobody acknowledges */

static const struct pwm_dt_spec buzzer_pwm = PWM_DT_SPEC_GET(DT_NODELABEL(pwm0));
static const struct pwm_dt_spec vibe_pwm = PWM_DT_SPEC_GET(DT_NODELABEL(pwm1));

static struct k_work_delayable buzzer_off_work;
static struct k_work_delayable vibe_off_work;
static struct k_work_delayable alarm_pulse_work;

static bool alarm_active;
static bool alarm_vibrate;
static bool alarm_beep;
static bool alarm_pulse_on;
static int64_t alarm_started_ms;

static int buzzer_set(uint32_t freq_hz)
{
	if (freq_hz == 0) {
		return pwm_set_pulse_dt(&buzzer_pwm, 0);
	}
	uint32_t period_ns = NSEC_PER_SEC / freq_hz;
	return pwm_set_dt(&buzzer_pwm, period_ns, period_ns / 2 /* 50% duty */);
}

static int vibe_set(bool on)
{
	/* Full-power on/off; PWM channel is available for intensity ramping
	 * later without a hardware change if that turns out to matter.
	 */
	return pwm_set_pulse_dt(&vibe_pwm, on ? vibe_pwm.period : 0);
}

static void buzzer_off_handler(struct k_work *work)
{
	ARG_UNUSED(work);
	buzzer_set(0);
}

static void vibe_off_handler(struct k_work *work)
{
	ARG_UNUSED(work);
	vibe_set(false);
}

static void alarm_pulse_handler(struct k_work *work)
{
	ARG_UNUSED(work);

	if (!alarm_active) {
		return;
	}

	if (k_uptime_get() - alarm_started_ms > ALARM_TIMEOUT_MS) {
		haptics_stop();
		return;
	}

	alarm_pulse_on = !alarm_pulse_on;
	if (alarm_beep) {
		buzzer_set(alarm_pulse_on ? 2700 : 0); /* ~2.7kHz: stock A158-ish alarm pitch */
	}
	if (alarm_vibrate) {
		vibe_set(alarm_pulse_on);
	}

	k_work_schedule(&alarm_pulse_work,
			K_MSEC(alarm_pulse_on ? ALARM_PULSE_ON_MS : ALARM_PULSE_OFF_MS));
}

int haptics_init(void)
{
	if (!pwm_is_ready_dt(&buzzer_pwm) || !pwm_is_ready_dt(&vibe_pwm)) {
		LOG_ERR("Haptics PWM not ready");
		return -ENODEV;
	}

	k_work_init_delayable(&buzzer_off_work, buzzer_off_handler);
	k_work_init_delayable(&vibe_off_work, vibe_off_handler);
	k_work_init_delayable(&alarm_pulse_work, alarm_pulse_handler);
	return 0;
}

int haptics_beep(uint32_t freq_hz, uint32_t duration_ms)
{
	int err = buzzer_set(freq_hz);
	if (err) {
		return err;
	}
	return k_work_schedule(&buzzer_off_work, K_MSEC(duration_ms));
}

int haptics_vibrate(uint32_t duration_ms)
{
	int err = vibe_set(true);
	if (err) {
		return err;
	}
	return k_work_schedule(&vibe_off_work, K_MSEC(duration_ms));
}

int haptics_alarm(bool vibrate, bool beep)
{
	if (!vibrate && !beep) {
		return -EINVAL;
	}

	alarm_active = true;
	alarm_vibrate = vibrate;
	alarm_beep = beep;
	alarm_pulse_on = false;
	alarm_started_ms = k_uptime_get();

	return k_work_schedule(&alarm_pulse_work, K_NO_WAIT);
}

int haptics_stop(void)
{
	alarm_active = false;
	k_work_cancel_delayable(&alarm_pulse_work);
	buzzer_set(0);
	vibe_set(false);
	return 0;
}
