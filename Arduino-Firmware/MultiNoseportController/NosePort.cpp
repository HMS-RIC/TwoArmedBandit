
#include "NosePort.h"
#include <Arduino.h>

extern void DEBUG(String message);

int NosePort::nosePortListSize = 0;
NosePort* NosePort::nosePortList[MAX_PORT_LIST_SIZE];

NosePort::NosePort(int beambreakPin, int solenoidPin) {
  _beambreakPin = beambreakPin;
  _solenoidPin = solenoidPin;
  _ledPin = 0;
  _rewardActivated = false;
  _rewardDuration_us = 0;
  _singleReward = false;

  _duringReward = 0;
  _rewardStartTime_us = 0;

  _rewardActivePin = 0;
  _rewardActivePinHigh = false;

  _laserPin = 0;
  _laserActivated = false;
  _laserStimEndTrigType = LASER_END_TRIG_TIME; // default to timed laser stim duration
  _laserStimDelay_us = 0;
  _laserStimDur_us = 0;
  _laserPulseDur_us = 0;
  _laserPulsePeriod_us = 0;

  _duringLaserStim = false;
  _laserStimStartTime_us = 0;
  _laserOn = false;

  pinMode(_beambreakPin, INPUT);
  _noseIn = (digitalRead(_beambreakPin) == HIGH);

  pinMode(_solenoidPin, OUTPUT);
  digitalWrite(_solenoidPin, LOW);

  if (nosePortListSize < MAX_PORT_LIST_SIZE-1) {
    nosePortList[nosePortListSize] = this;
    nosePortListSize += 1;
    _nosePortNumber = nosePortListSize; //nosePort number is ones-based
  } else {
    _nosePortNumber = 0;
  }

  logToUSB('N');

  DEBUG(String("New NosePort: ")+_nosePortNumber);
  DEBUG(String("- beam pin: ")+_beambreakPin);
  DEBUG(String("- sol pin: ")+_solenoidPin);

}

void NosePort::setRewardDuration(long duration) {
  DEBUG("Updated Duration");
  _rewardDuration_us = duration * 1000;
}

void NosePort::setActivated(bool activated) {
  DEBUG("Updated Activation State");
  _rewardActivated = activated;
}

void NosePort::setSingleReward(bool singleReward) {
  _singleReward = singleReward;
}

void NosePort::noseIn() {
  //DEBUG(String("Nose In — nosePort ")+_nosePortNumber);
  DEBUG(String("Nose In - nosePort ")+_nosePortNumber);
  _noseIn = true;
  if ((_rewardActivated) && (_rewardDuration_us > 0)) {
    // set timer; set pin high
    _duringReward = true;
    _rewardStartTime_us = micros();
    digitalWrite(_solenoidPin, HIGH);
    // log rewarded nose in
    logToUSB('D');
  } else {
    // log unrewarded noseIn
    logToUSB('I');
  }
  if (_singleReward) {
    setActivated(false);
  }
  // The following two commands must happen in this order:
  // 1. first broadcast nose-in event to all ports (as a possible trigger to end their laser stim)
  sendNoseInBroadcast();
  // 2. next, start any new laser stim triggerd by this nose poke
  if (_laserActivated) {
    startLaserStim();
  }
}

void NosePort::noseOut() {
  DEBUG(String("Nose Out - nosePort ")+_nosePortNumber);
  _noseIn = false;
  // log noseOut
  logToUSB('O');
  if ((_duringLaserStim) && (_laserStimEndTrigType == LASER_END_TRIG_NOSE_OUT)) {
    endLaserStim();
  }
}

void NosePort::sendNoseInBroadcast() {
  for (int i=0; i<nosePortListSize; i++) {
    NosePort* p = nosePortList[i];
    p->receiveNoseInBroadcast();
  }
}

void NosePort::receiveNoseInBroadcast() {
  if ((_duringLaserStim) && (_laserStimEndTrigType == LASER_END_TRIG_NOSE_IN)) {
    endLaserStim();
  }
}


unsigned long pulseStartTime_us = 0;
void NosePort::update() {
  if (_rewardActivePin > 0) {
    bool currentRewardActivePinState = (digitalRead(_rewardActivePin) == HIGH);
    if (_rewardActivePinHigh != currentRewardActivePinState) { // if there's been a change in state
      _rewardActivePinHigh = currentRewardActivePinState;
      setActivated(_rewardActivePinHigh);
    }
  }
  bool currentNosePortState = (digitalRead(_beambreakPin) == HIGH);
  if (_noseIn != currentNosePortState) { // if there's been a change in state
    if (currentNosePortState) {
      noseIn();
    } else {
      noseOut();
    }
  }
  if (_duringReward) {
    if (micros() - _rewardStartTime_us > _rewardDuration_us ) { // time comparison is corrected for overflow
      digitalWrite(_solenoidPin, LOW);
      _duringReward = false;
    }
  }
  if (_duringLaserStim) {
    // compute time since stim was triggered
    unsigned long stimTime = micros() - _laserStimStartTime_us;
    // check if we're past the delay period
    //  (if not, do nothing)
    if (stimTime > _laserStimDelay_us ) {
      // if we are past the delay, compute time since delay ended (i.e., time into pulsing)
      stimTime = stimTime - _laserStimDelay_us;
      if (stimTime >= _laserStimDur_us) {
        // if _laserStimDur is exceeded then end the stim
        // NOTE: For fixed-duration laser stim, _laserStimDur is the specified duration
        //       For variable-duration stim, _laserStimDur is the max duration timeout
        endLaserStim();
        if (_laserStimEndTrigType != LASER_END_TRIG_TIME) {
          logToUSB('T');
        }
      } else {
        // otherwise, turn laser on/off based on pulse parameters:
        if ((stimTime >= pulseStartTime_us) && (!_laserOn)) {
          digitalWrite(_laserPin, HIGH);
          _laserOn = true;          
        } else if ((stimTime >= pulseStartTime_us + _laserPulseDur_us) && (_laserOn)) {
          // We're at end of current pulse.
          // Compute next pulse start time:
          pulseStartTime_us += _laserPulsePeriod_us;
          // Turn off laser unless next pulse starts now (i.e., if pulseDur==pulsePeriod)
          if (stimTime < pulseStartTime_us){
            digitalWrite(_laserPin, LOW);
            _laserOn = false;
          }
        }
      }
    }
  }
}

void NosePort::deliverReward() {
  DEBUG(String("Reward - nosePort ") + _nosePortNumber);
  DEBUG(String("       - duration ") + (_rewardDuration_us / 1000));

  if (_rewardDuration_us > 0) {
    // set timer; set pin high; log
    _duringReward = true;
    _rewardStartTime_us = micros();
    digitalWrite(_solenoidPin, HIGH);
    logToUSB('R');

    // TODO Prevent rewards from overlapping; stop reward on nose out
  }
}

void NosePort::setRewardActivePin(int pin) {
  _rewardActivePin = pin;
  pinMode(_rewardActivePin, INPUT);
}

// LED methods
void NosePort::setLEDPin(int pin) {
  _ledPin = pin;
  pinMode(_ledPin, OUTPUT);
  digitalWrite(_ledPin, LOW);
}

void NosePort::ledOn() {
  if (_ledPin > 0) {
    digitalWrite(_ledPin, HIGH);
  }
}

void NosePort::ledOff() {
  if (_ledPin > 0) {
    digitalWrite(_ledPin, LOW);
  }
}

// Laser methods
void NosePort::setLaserPin(int pin) {
  _laserPin = pin;
  pinMode(_laserPin, OUTPUT);
  digitalWrite(_laserPin, LOW);
}

void NosePort::setLaserEndTrigger(unsigned int trigType) {
  if (trigType < NUM_LASER_END_TRIG_TYPES) {
    _laserStimEndTrigType = trigType;
  }
}

void NosePort::setLaserDelay(long delay) {
  _laserStimDelay_us = delay * 1000;
}

void NosePort::setLaserStimDuration(long stimDur) {
  _laserStimDur_us = stimDur * 1000;
}

void NosePort::setLaserPulseDuration(long pulseDur) {
  _laserPulseDur_us = pulseDur * 1000;
}

void NosePort::setLaserPulsePeriod(long pulsePeriod) {
  _laserPulsePeriod_us = pulsePeriod * 1000;
}

void NosePort::setLaserActive(bool activated) {
  if (activated) {
    if (_laserPin > 0) {
      _laserActivated = true;
    }
  } else {
    _laserActivated = false;
  }
}

void NosePort::startLaserStim() {
  DEBUG(String("Laser Stim START - nosePort ")+_nosePortNumber);
  
  if (_laserPin > 0) {  
    _duringLaserStim = true;
    _laserStimStartTime_us = micros();  
    logToUSB('L'); 

    pulseStartTime_us = 0;
  }
}

void NosePort::endLaserStim() {
  DEBUG(String("Laser Stim END   - nosePort ")+_nosePortNumber);
  _duringLaserStim = false;
  digitalWrite(_laserPin, LOW);
  _laserOn = false;
  logToUSB('l'); 
}


// debug & logging methods
void NosePort::identify() {
  DEBUG(String("NosePort Num: ")+_nosePortNumber);
  DEBUG(String("- beam pin: ")+_beambreakPin);
  DEBUG(String("- sol pin: ")+_solenoidPin);
  DEBUG(String("- LED pin: ")+_ledPin);
}

void NosePort::logToUSB(char message) {
  String logMessgage = String(message);
  logMessgage += ' ';
  logMessgage += _nosePortNumber;
  Serial.println(logMessgage.c_str());
}


// ======= Class Methods ========

void NosePort::updateAll() {
  for (int i=0; i<NosePort::nosePortListSize; i++) {
    NosePort* p = NosePort::nosePortList[i];
    p->update();
  }
}

void NosePort::interpretCommand(String message) {
  message.trim(); // remove leading and trailing white space
  int len = message.length();
  if (len==0) {
    Serial.println("# emptyMessage"); // "#" means error
    return;
  }
  char command = message[0]; // the command is the first char of a message
  String parameters = message.substring(1);
  parameters.trim();

  String intString = "";
  while ((parameters.length() > 0) && (isDigit(parameters[0]))) {
    intString += parameters[0];
    parameters.remove(0,1);
  }
  unsigned long arg1 = intString.toInt();

  parameters.trim();
  intString = "";
  while ((parameters.length() > 0) && (isDigit(parameters[0]))) {
    intString += parameters[0];
    parameters.remove(0,1);
  }
  unsigned long arg2 = intString.toInt();


  DEBUG(String("Command: ")+command);
  DEBUG(String("Argument 1: ")+arg1);
  DEBUG(String("Argument 2: ")+arg2);

  if (command == '^') { // ^: handshake character
    Serial.println("^");
    return;
  }


  if (command == 'N') { // N: new nosePort
    // arg1 is beambreak pin
    // arg2 is solenoid pin
    new NosePort(arg1, arg2);
  } else {

    if ((arg1 <= 0) || (arg1 > nosePortListSize)) {
      // Bad NosePort Number
      Serial.print("# badPortNumber: \""); // "#" means error
      Serial.print(message);
      Serial.println("\"");
      return;
    }
    int nosePortNum = arg1;

    if (command == 'D') { // D: set reward duration
      nosePortList[nosePortNum-1]->setRewardDuration(arg2);
    } else if (command == 'A') { // A: set reward activation state
      nosePortList[nosePortNum-1]->setActivated(arg2);
    } else if (command == 'S') { // S: set single-reward state
      nosePortList[nosePortNum-1]->setSingleReward(arg2);
    } else if (command == 'R') { // R: deliver reward
      nosePortList[nosePortNum-1]->deliverReward();
    } else if (command == 'W') { // W: set reward active pin
      nosePortList[nosePortNum-1]->setRewardActivePin(arg2);

    } else if (command == 'L') { // L: set LED pin
      nosePortList[nosePortNum-1]->setLEDPin(arg2);
    } else if (command == 'O') { // L: turn LED on
      nosePortList[nosePortNum-1]->ledOn();
    } else if (command == 'F') { // L: turn LED off
      nosePortList[nosePortNum-1]->ledOff();

    } else if (command == 'P') { // P: set laser pin
      nosePortList[nosePortNum-1]->setLaserPin(arg2);
    } else if (command == 'Y') { // Y: set laser delay
      nosePortList[nosePortNum-1]->setLaserDelay(arg2);
    } else if (command == 'G') { // G: set laser end trigger (0:time, 1:nose-out, 2:nose-in)
      nosePortList[nosePortNum-1]->setLaserEndTrigger(arg2);
    } else if (command == 'T') { // T: set laser stim duration
      nosePortList[nosePortNum-1]->setLaserStimDuration(arg2);
    } else if (command == 'U') { // U: set laser pulse duration
      nosePortList[nosePortNum-1]->setLaserPulseDuration(arg2);
    } else if (command == 'I') { // I: set laser pulse period
      nosePortList[nosePortNum-1]->setLaserPulsePeriod(arg2);
    } else if (command == 'V') { // V: set laser activation state
      nosePortList[nosePortNum-1]->setLaserActive(arg2);

    } else { // unknown command
      Serial.print("# unknownMessage: \""); // "#" means error
      Serial.print(message);
      Serial.println("\"");

    }
  }
}

