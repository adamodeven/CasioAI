/*
 * SPI driver for the external PCF8551 segment LCD driver IC (see
 * hardware/FEASIBILITY.md's addendum on why nRF52832 needs one). This is
 * the single highest-risk file in this firmware, for two independent
 * reasons — read both before trusting anything here:
 *
 * 1. PCF8551's exact command protocol (mode-set opcode, display-RAM write
 *    addressing) came from its product brief, not the full instruction-set
 *    timing diagrams in the datasheet (which this environment couldn't
 *    fetch — see hardware/FEASIBILITY.md's note on restricted web access).
 *    `pcf8551_send_command` / `pcf8551_write_display_ram` below follow the
 *    common shape for this class of segment driver (mode-set byte, then a
 *    display-RAM write command followed by sequential data bytes) but the
 *    exact opcodes are placeholders — cross-check against NXP's full
 *    PCF8551 datasheet before flashing real hardware.
 *
 * 2. The mapping from "hour tens digit" etc. to a specific segment/backplane
 *    bit position is fundamentally unknowable without the real A158WE LCD
 *    glass in hand (see PINMAP punch list item "LCD segment/backplane
 *    count"). The SEG_OFFSET_* constants below are named placeholders,
 *    not measurements — every one of them needs to be filled in from a
 *    continuity test against the physical display before this drives
 *    anything meaningful.
 *
 * The seven-segment encoding table itself (which segments a-g light up for
 * each digit 0-9) *is* a fixed, sourceable fact independent of the specific
 * watch, so that part is real.
 */
#include <string.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/util.h>

#include "lcd_driver.h"

LOG_MODULE_REGISTER(lcd_driver, LOG_LEVEL_INF);

#define PCF8551_RAM_BYTES 18 /* 36 segments x 4 backplanes / 8 bits, per product brief */

/* --- TODO: real segment/backplane offsets, from a continuity test --- */
#define SEG_OFFSET_HOUR_TENS   0
#define SEG_OFFSET_HOUR_UNITS  1
#define SEG_OFFSET_MINUTE_TENS 2
#define SEG_OFFSET_MINUTE_UNITS 3
#define SEG_BIT_COLON          BIT(0) /* placeholder bit position, byte TBD */
#define SEG_OFFSET_TEMP_LOW_TENS  6
#define SEG_OFFSET_TEMP_LOW_UNITS 7
#define SEG_OFFSET_TEMP_HIGH_TENS  8
#define SEG_OFFSET_TEMP_HIGH_UNITS 9
#define SEG_BIT_ALARM_ICON      BIT(1) /* placeholder */
#define SEG_OFFSET_ALARM_ICON   10
#define SEG_BIT_LOW_BATTERY_ICON BIT(2) /* placeholder */
#define SEG_OFFSET_LOW_BATTERY  10

/* Standard 7-segment a-g bit encoding (bit0=a … bit6=g), digits 0-9. This
 * part is a real, sourceable fact — not a placeholder like the offsets
 * above.
 */
static const uint8_t SEVEN_SEG_DIGITS[10] = {
	0x3F, /* 0 */
	0x06, /* 1 */
	0x5B, /* 2 */
	0x4F, /* 3 */
	0x66, /* 4 */
	0x6D, /* 5 */
	0x7D, /* 6 */
	0x07, /* 7 */
	0x7F, /* 8 */
	0x6F, /* 9 */
};

static const struct spi_dt_spec lcd_spi = SPI_DT_SPEC_GET(
	DT_ALIAS(lcd_driver), SPI_WORD_SET(8) | SPI_TRANSFER_MSB, 0);

static uint8_t segment_ram[PCF8551_RAM_BYTES];

static int pcf8551_send(const uint8_t *data, size_t len)
{
	struct spi_buf buf = {.buf = (void *)data, .len = len};
	struct spi_buf_set tx = {.buffers = &buf, .count = 1};
	return spi_write_dt(&lcd_spi, &tx);
}

static int pcf8551_send_command(uint8_t cmd)
{
	/* Placeholder single-byte command frame — see file header. */
	return pcf8551_send(&cmd, 1);
}

static int pcf8551_write_display_ram(void)
{
	/* Placeholder: 0x40 = "write display RAM starting at address 0" in
	 * this class of driver IC, followed by the full RAM image.
	 */
	uint8_t frame[1 + PCF8551_RAM_BYTES];
	frame[0] = 0x40;
	memcpy(&frame[1], segment_ram, PCF8551_RAM_BYTES);
	return pcf8551_send(frame, sizeof(frame));
}

static void set_digit(uint8_t offset, uint8_t value)
{
	if (offset >= PCF8551_RAM_BYTES || value > 9) {
		return;
	}
	segment_ram[offset] = SEVEN_SEG_DIGITS[value];
}

int lcd_driver_init(void)
{
	if (!spi_is_ready_dt(&lcd_spi)) {
		LOG_ERR("LCD driver SPI bus not ready");
		return -ENODEV;
	}

	memset(segment_ram, 0, sizeof(segment_ram));

	/* Placeholder: 0x00 = "mode set: static/normal operation, display on"
	 * in this class of driver IC.
	 */
	int err = pcf8551_send_command(0x00);
	if (err) {
		return err;
	}

	return lcd_driver_flush();
}

int lcd_driver_set_time(uint8_t hour24, uint8_t minute, bool colon_on)
{
	set_digit(SEG_OFFSET_HOUR_TENS, hour24 / 10);
	set_digit(SEG_OFFSET_HOUR_UNITS, hour24 % 10);
	set_digit(SEG_OFFSET_MINUTE_TENS, minute / 10);
	set_digit(SEG_OFFSET_MINUTE_UNITS, minute % 10);

	if (colon_on) {
		segment_ram[SEG_OFFSET_MINUTE_TENS] |= SEG_BIT_COLON;
	} else {
		segment_ram[SEG_OFFSET_MINUTE_TENS] &= ~SEG_BIT_COLON;
	}
	return 0;
}

int lcd_driver_set_temperature(int8_t low_fahrenheit, int8_t high_fahrenheit)
{
	uint8_t low_abs = (uint8_t)(low_fahrenheit < 0 ? -low_fahrenheit : low_fahrenheit);
	uint8_t high_abs = (uint8_t)(high_fahrenheit < 0 ? -high_fahrenheit : high_fahrenheit);

	set_digit(SEG_OFFSET_TEMP_LOW_TENS, (low_abs / 10) % 10);
	set_digit(SEG_OFFSET_TEMP_LOW_UNITS, low_abs % 10);
	set_digit(SEG_OFFSET_TEMP_HIGH_TENS, (high_abs / 10) % 10);
	set_digit(SEG_OFFSET_TEMP_HIGH_UNITS, high_abs % 10);
	/* Negative-temperature minus sign glyph is another unmapped segment —
	 * see file header; not wired up until the real segment map exists.
	 */
	return 0;
}

int lcd_driver_set_alarm_icon(bool on)
{
	if (on) {
		segment_ram[SEG_OFFSET_ALARM_ICON] |= SEG_BIT_ALARM_ICON;
	} else {
		segment_ram[SEG_OFFSET_ALARM_ICON] &= ~SEG_BIT_ALARM_ICON;
	}
	return 0;
}

int lcd_driver_set_low_battery_icon(bool on)
{
	if (on) {
		segment_ram[SEG_OFFSET_LOW_BATTERY] |= SEG_BIT_LOW_BATTERY_ICON;
	} else {
		segment_ram[SEG_OFFSET_LOW_BATTERY] &= ~SEG_BIT_LOW_BATTERY_ICON;
	}
	return 0;
}

int lcd_driver_flush(void)
{
	return pcf8551_write_display_ram();
}
