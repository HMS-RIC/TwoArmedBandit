
#ifndef NosePort_h
#define NosePort_h

#include <WString.h>

const int MAX_PORT_LIST_SIZE = 32;

// Laser Stim End Triggers
# define LASER_END_TRIG_TIME 0
# define LASER_END_TRIG_NOSE_OUT 1
# define LASER_END_TRIG_NOSE_IN 2
# define NUM_LASER_END_TRIG_TYPES 3

class NosePort {

private:
  int _nosePortNumber;
  int _beambreakPin;
  int _solenoidPin;
  bool _rewardActivated;
  unsigned long _rewardDuration_us;
  bool _singleReward;
  int _ledPin;
  int _rewardActivePin;
  bool _rewardActivePinHigh;
  int _laserPin;
  bool _laserActivated;
  unsigned long _laserStimDelay_us;
  unsigned int _laserStimEndTrigType;
  unsigned long _laserStimDur_us;
  unsigned long _laserPulseDur_us;
  unsigned long _laserPulsePeriod_us;
  bool _duringLaserStim;
  unsigned long _laserStimStartTime_us;
  bool _laserOn;
 
  bool _noseIn;
  bool _duringReward;
  unsigned long _rewardStartTime_us;

public:

  // class methods
  static void interpretCommand(String message);
  static void updateAll();

  // class data
  static NosePort* nosePortList[MAX_PORT_LIST_SIZE];
  static int nosePortListSize;

  // consrtuctors / destructors
  NosePort(int beambreakPin, int solenoidPin);
  //~NosePort();

  // public methods                           All API times are in milliseconds:
  void setRewardDuration(long duration);      // in ms
  void setActivated(bool activated);
  void setRewardActivePin(int pin);
  void setSingleReward(bool singleReward);
  void deliverReward();
  void noseIn();
  void noseOut();
  void sendNoseInBroadcast();
  void receiveNoseInBroadcast();
  void setLEDPin(int pin);
  void ledOn();
  void ledOff();
  void setLaserPin(int pin);
  void setLaserDelay(long delay);             // in ms
  void setLaserEndTrigger(unsigned int trigType);      // trigger types defined above
  void setLaserStimDuration(long stimDur);    // in ms
  void setLaserPulseDuration(long pulseDur);  // in ms
  void setLaserPulsePeriod(long pulseRate);   // in ms
  void setLaserActive(bool activated);
  void startLaserStim();
  void endLaserStim();
  void update();
  void logToUSB(char message);

  void identify(); // for debugging

};



#endif
