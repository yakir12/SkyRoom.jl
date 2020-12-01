#include <PWM.h>
#include <PacketSerial.h> // for the COBS

PacketSerial myPacketSerial;

int pwmPin = 3;
int tachPin1 = 2;
int tachPin2 = 4;
int tachPin3 = 5;
unsigned long v;
uint8_t t[12];
uint8_t pwm;
uint8_t zerotime[12];

void setup()
{
  myPacketSerial.begin(9600);
  myPacketSerial.setPacketHandler(&onPacketReceived);

  InitTimersSafe();
  bool success = SetPinFrequencySafe(pwmPin, 25000);
  if (success) {
    //    pinMode(tachPin, OUTPUT);
    digitalWrite(tachPin1, HIGH);
    digitalWrite(tachPin2, HIGH);
    digitalWrite(tachPin3, HIGH);
  }
  delay(100);
  pwmWrite(pwmPin, 0);

  for (uint8_t i = 0; i < 12; ++i)
    zerotime[i] = 0;
}

void loop()
{
  myPacketSerial.update();
  if (pwm < 20) {
    delay(100);
    myPacketSerial.send(zerotime, 12);
  }
  else {
    v = pulseIn(tachPin1, HIGH, 100000);
    t[0] = v >> 24;
    t[1] = v >> 16;
    t[2] = v >>  8;
    t[3] = v;
    v = pulseIn(tachPin2, HIGH, 100000);
    t[4] = v >> 24;
    t[5] = v >> 16;
    t[6] = v >>  8;
    t[7] = v;
    v = pulseIn(tachPin3, HIGH, 100000);
    t[8] = v >> 24;
    t[9] = v >> 16;
    t[10] = v >>  8;
    t[11] = v;
    myPacketSerial.send(t, 12);
  }
}

void onPacketReceived(const uint8_t* buffer, size_t size)
{
  pwm = buffer[0];
  pwmWrite(pwmPin, pwm);
}
