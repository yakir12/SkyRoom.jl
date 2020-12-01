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
  nstars = size / 4;
  strip.clear();
  for (int i = 0; i < 4 * nstars; i = i + 4) {
    strip.setPixelColor(buffer[i], buffer[i + 1], buffer[i + 2], buffer[i + 3]);
  }
  strip.show();
}
