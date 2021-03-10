/*
 * Outputs a raw 24-bit image of 256x512 pixels containing a test depth
 * palette.
 * (C)2011 Mike Bourgeous
 */
#include <stdio.h>
#include <stdint.h>

uint8_t clamp(int c)
{
	if(c < 0)
		return 0;
	if(c > 255)
		return 255;
	return c;
}

int main()
{
	uint8_t r, g, b;
	int x, y;

	for(y = 0; y < 512; y++) {
		for(x = 0; x < 256; x++) {
			b = clamp(y);
			g = clamp(y - 128);
			r = clamp(y - 256);
			fwrite(&r, 1, 1, stdout);
			fwrite(&g, 1, 1, stdout);
			fwrite(&b, 1, 1, stdout);
		}
	}

	return 0;
}

