#ifndef POWER_H_
#define POWER_H_

#include "watch_protocol.h"

/* Starts the once-a-minute clock tick that keeps the LCD's time/temp
 * digits current and reports status back to the phone. Actual low-power
 * idling between events is Zephyr's PM subsystem (CONFIG_PM /
 * CONFIG_PM_DEVICE in prj.conf) doing its job automatically whenever no
 * thread is runnable — there's no separate "go to sleep" call needed as
 * long as the rest of the firmware stays interrupt/event-driven (GPIO
 * interrupts, BLE callbacks, PDM DMA) instead of polling, which is how
 * buttons.c/audio_capture.c/ble_service.c are all written.
 */
int power_init(void);

void power_apply_time_sync(const struct watch_time_sync_payload *sync);
void power_apply_temperature(const struct watch_temperature_payload *temp);

#endif /* POWER_H_ */
