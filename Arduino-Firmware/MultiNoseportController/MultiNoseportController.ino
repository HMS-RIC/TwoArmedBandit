
#include "NosePort.h"

// Set DEBUG_MODE to 1 for debug mode, otherwise set to 0
const bool DEBUG_MODE = 0;
const int debugPin = 12;  // Pin 12 will be in use in DEBUG MODE
bool alternateLoopFlag = false; // DEBUG
void DEBUG(String message) {
  if (DEBUG_MODE) {
    Serial.println(message.c_str());
  }
}
void debug_setup() {
  if (DEBUG_MODE) {
    pinMode(debugPin, OUTPUT);
  }
}
void debug_loop() {
  if (DEBUG_MODE) {
    digitalWrite(debugPin, alternateLoopFlag);
    alternateLoopFlag = !alternateLoopFlag;
  }
}
// --- end debug stuff ---



void setup() {
  // set up USB communication at 115200 baud
  Serial.begin(115200);
  // tell PC that we're running by sending '^' message
  Serial.println("^");

  debug_setup(); 
}

void loop() {
  // read from USB, if available
  readFromUSB();
  // update the status of all NosePorts
  NosePort::updateAll();

  debug_loop();
}

void readFromUSB() {
  // read from USB, if available
  static String usbMessage = ""; // initialize usbMessage to empty string,
                                 // happens once at start of program
  if (Serial.available() > 0) {
    // read next char if available
    char inByte = Serial.read();
    if (inByte == '\n') {
      // the new-line character ('\n') indicates a complete message
      // so interprete the message and then clear buffer
      NosePort::interpretCommand(usbMessage);
      usbMessage = ""; // clear message buffer
    } else {
      // append character to message buffer
      usbMessage = usbMessage + inByte;
    }
  }
}
