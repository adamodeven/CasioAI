#ifndef LCD_DRIVER_H_
#define LCD_DRIVER_H_

#include <stdbool.h>
#include <stdint.h>

int lcd_driver_init(void);

/* All setters just update the in-memory segment buffer; call
 * lcd_driver_flush() to actually push it to the PCF8551 over SPI. Batch a
 * frame's worth of changes and flush once, rather than flushing per field.
 */
int lcd_driver_set_time(uint8_t hour24, uint8_t minute, bool colon_on);
int lcd_driver_set_temperature(int8_t low_fahrenheit, int8_t high_fahrenheit);
int lcd_driver_set_alarm_icon(bool on);
int lcd_driver_set_low_battery_icon(bool on);
int lcd_driver_flush(void);

#endif /* LCD_DRIVER_H_ */
