#include <Adafruit_DotStar.h>
#include <PacketSerial.h> // for the COBS

int nstars;

PacketSerial myPacketSerial;
#define NUMPIXELS 300 // Number of LEDs in strip

// Here's how to control the LEDs from any two pins:
#define DATAPIN    4
#define CLOCKPIN   5
Adafruit_DotStar strip(NUMPIXELS, DATAPIN, CLOCKPIN, DOTSTAR_BGR);

void setup() {
    myPacketSerial.begin(9600);
    myPacketSerial.setPacketHandler(&onPacketReceived);

    strip.begin(); // Initialize pins for output
    strip.clear();
    strip.show();  // Turn all LEDs off ASAP

}

void loop() {
    myPacketSerial.update();
}

void onPacketReceived(const uint8_t* buffer, size_t size)
{
    nstars = size / 5;
    strip.clear();
    for (int i = 0; i < 5 * nstars; i = i + 5) {
        int combined = (buffer[i] * 256) + buffer[i + 1];
        strip.setPixelColor(combined, buffer[i + 2], buffer[i + 3], buffer[i + 4]);
    }
    strip.show();
}
