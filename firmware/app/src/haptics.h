#ifndef HAPTICS_H_
#define HAPTICS_H_

#include <stdbool.h>
#include <stdint.h>

int haptics_init(void);

/* Fire-and-forget short feedback (button acknowledgment, etc). */
int haptics_beep(uint32_t freq_hz, uint32_t duration_ms);
int haptics_vibrate(uint32_t duration_ms);

/* Starts the repeating alarm pattern per the spec's vibrate/beep modes
 * (WatchStatusFlags.alarmVibrate / alarmBeep on the phone side); at least
 * one of vibrate/beep should be true. Runs until haptics_stop() — e.g. on
 * any button press acknowledging the alarm — or an internal timeout.
 */
int haptics_alarm(bool vibrate, bool beep);
int haptics_stop(void);

#endif /* HAPTICS_H_ */
