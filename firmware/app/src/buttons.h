#ifndef BUTTONS_H_
#define BUTTONS_H_

#include "watch_protocol.h"

/* Sets up GPIO interrupts for all four physical buttons. See
 * ../PINMAP.md#button-remapping for the rationale behind which physical
 * button does what — this is a rev1 firmware UX decision, not something
 * from the source spec, and easy to revisit once the watch is in hand.
 */
int buttons_init(void);

/* Called whenever the phone writes a new call state, so the capture/talk
 * buttons can temporarily switch to answer/reject while a call rings.
 */
void buttons_set_call_state(enum watch_call_state state);

#endif /* BUTTONS_H_ */
