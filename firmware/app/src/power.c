/*
 * Time/temperature state + the once-a-minute LCD/status tick. No hardware
 * RTC peripheral needed: time is tracked as a phone-supplied Unix-seconds
 * anchor plus Zephyr's monotonic k_uptime_get(), which itself already runs
 * on the SoC's low-power RTC1 peripheral under the hood — so this stays
 * accurate across sleep without any extra driver code here.
 */
#include <time.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include "ble_service.h"
#include "haptics.h"
#include "lcd_driver.h"
#include "power.h"

LOG_MODULE_REGISTER(power, LOG_LEVEL_INF);

static int64_t sync_unix_seconds;
static int64_t sync_uptime_ms;
static int8_t utc_offset_quarter_hours;
static bool have_time_sync;

static int8_t cached_low_f;
static int8_t cached_high_f;

static struct k_work_delayable minute_tick_work;

/* No fuel gauge on a coin cell in rev1 — reporting a fixed 100% until a
 * real VDD-based estimate (nRF52832's SAADC against the CR2016 discharge
 * curve) is calibrated against actual hardware. Flagged in the punch list.
 */
static uint8_t estimate_battery_percent(void)
{
	return 100;
}

static void minute_tick_handler(struct k_work *work)
{
	ARG_UNUSED(work);

	if (have_time_sync) {
		int64_t now_unix = sync_unix_seconds +
				    (k_uptime_get() - sync_uptime_ms) / 1000;
		now_unix += (int64_t)utc_offset_quarter_hours * 15 * 60;

		time_t now_time = (time_t)now_unix;
		struct tm tm_now;
		gmtime_r(&now_time, &tm_now);

		lcd_driver_set_time((uint8_t)tm_now.tm_hour, (uint8_t)tm_now.tm_min, true);
		lcd_driver_set_temperature(cached_low_f, cached_high_f);
		lcd_driver_flush();
	}

	struct watch_status_payload status = {
		.battery_percent = estimate_battery_percent(),
		.flags = 0,
		.firmware_version = 1,
	};
	if (status.battery_percent < 15) {
		status.flags |= WATCH_STATUS_FLAG_LOW_BATTERY;
		lcd_driver_set_low_battery_icon(true);
	}
	ble_service_notify_status(&status);

	k_work_schedule(&minute_tick_work, K_SECONDS(60));
}

int power_init(void)
{
	k_work_init_delayable(&minute_tick_work, minute_tick_handler);
	return k_work_schedule(&minute_tick_work, K_NO_WAIT);
}

void power_apply_time_sync(const struct watch_time_sync_payload *sync)
{
	sync_unix_seconds = sync->unix_seconds;
	sync_uptime_ms = k_uptime_get();
	utc_offset_quarter_hours = sync->utc_offset_quarter_hours;
	have_time_sync = true;

	/* Refresh immediately rather than waiting up to 60s for the next tick. */
	k_work_reschedule(&minute_tick_work, K_NO_WAIT);
}

void power_apply_temperature(const struct watch_temperature_payload *temp)
{
	cached_low_f = temp->low_fahrenheit;
	cached_high_f = temp->high_fahrenheit;
}
