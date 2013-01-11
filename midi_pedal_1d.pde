#include <Bounce.h>
// 
// Sparkfun Midi shield as midi controller for footpedals and maybe other things. 
//
// Steven Cogswell   steven.cogswell@gmail.com
// May 2011
//
// Sparkfun midi shield:  http://www.sparkfun.com/products/9595
// Some code and concept by Tubedogg 12/2006; fabian at tubedogg.de  http://www.arduino.cc/cgi-bin/yabb2/YaBB.pl?num=1165833586
// Uses the "Bounce" library by Thomas Ouellet Fredericks  http://arduino.cc/playground/Code/Bounce

// Rember to have the Sparkfun midi shield Run/Prog switch in the appropriate position.  

// The analog potentiometers on the Sparkfun board A0/A1 give 0-127 midi for full range.   You can change defaults with the 
// midiAnalogMax[]/midiAnalogMin[] Arrays below. 

// The three Sparkfun pushbuttons D2/D3/D4 are used to control modes.  This would have been easier with more buttons, but 
// this way you don't have to add any mods to the board.  
//
// Pushing D4 quickly (< 1000 ms) will turn the midi output on/off.  When it's off, move the controllers all you want,
// they won't output a midi value. 
// Pushing D4 and holding for > 1000 ms will put things into the "Programming mode", in which you can set min/max positions for 
// the various midi inputs.  
// When in programming mode, the LED STAT 1 (the red one) will flash a number of times corresponding with the midi input 
// you're changing (1 flash for on A0, 2 flashes for A1, 3 flashes for A2, etc, up to the max number of channels defined).
// Push D4 quickly (< 1000 ms) to increment which midi channel you're changing.  When you reach the last channel it starts over
// again with the first.  
// When in programming mode: 
// Push D3 - LED STAT 2 flashes, move pedal to minimum position and push D3 again.  Min value is stored
// Push D2 - LED STAT 2 flashes (faster), move pedal to maximum position and push D4 again.  Max value is stored. 
// This can be useful for pedals - like mine, where you really want the pedal to be "0" at the bottom of the range.  If you set
// the min input position to be before the end of travel, you're pretty guaranteed to get min value at end of travel.  Also good 
// if you get tired pushing the pedal all the way to the top, I suppose.  
// To leave programming mode, push D4 and hold for > 1000 ms.  LED STAT 1 (the red one) will stop flashing.  
//
// The arduino's LED (on the arduino board, not the sparkfun board) will flash when sending a midi message.  You can't see that 
// LED very well, but hey it's there.  Lets you confirm your inputs are actually being sent.  

// Defining DEBUG will make the code spit out the "midi' messages in a human-readable format at 9600bps for 
// convenience of debugging.  Otherwise it's 31250 bps. 
// 
#define DEBUG 1
#undef DEBUG     // Comment this line out to use 'debug' mode. 

// LED outputs and switch inputs 
#define LEDarduino 13  // LED on Arduino itself. 
#define LED1  6    // Note Sparkfun MIDI shield LED's are lit when "LOW" rather than "HIGH" (active low); 
#define LED2  7
#define D2  2     // Pushbuttons on Sparkfun MIDI Shield.  Buttons are HIGH when not pressed and LOW when pressed. 
#define D3  3
#define D4  4

// Parameters for debouncing the D2/D3/D4 button, uses the "Bounce" Library by Thomas Ouellet Fredericks
#define debounceDelay 50     // 50 ms is kind of long, but who cares? 
Bounce D2bounce = Bounce(D2, debounceDelay);
Bounce D3bounce = Bounce(D3, debounceDelay);
Bounce D4bounce = Bounce(D4, debounceDelay);

// select number of desired analog inputs (max 6)
// The Sparkfun midi shield by default has potentiometers wired to A0 and A1.  In my case I have an m-audio pedal wired
// into A2.   Note this counts from 0, so "input_no = 2" means 0,1,2 are actively being read. 
int input_no = 2;

// Midi parameters 
// These arrays are defined up to 6 because that's how many analog inputs the arduino has.   If you specify input_no as less
// than six then you just have unused parameters.  It was easier to leave it like this than to try and save five or six bytes of storage. 

// define variables for the controller data
int AnalogValue[6] = {
  0,0,0,0,0,0};    

// define the "lastValue" variables
int lastAnalogValue[6] = {
  0,0,0,0,0,0};

// select the midi Controller Number for each input
int midiCCselect[6] = {
  1,2,3,4,5,6};

// select threshold for each analog input  
int thresh[6] = {
  -1,-1,-1,-1,-1,-1};  

// Note that for Min/Max values, the analog potentiometers on the Sparkfun board are wired "backwards" from what I 
// expect when turning them.  The values are set such that turning the knob clockwise increases the midi value.  
// These can always be reprogrammed "on the fly" with the D4 programming mode.   You can use these to set defaults
// if you're consistent with your controllers' inputs. 

// Analog value for "0" Midi value
int midiAnalogMin[6] = {
  1024,1024,0,0,0,0};

// Analog value for Max Midi Value 
int midiAnalogMax[6] = {
  0,0,1024,1024,1024,1024};


long theMillis;    // Stores current millis() time on an execution through the main loop(). 

int isOn = false;             // Midi on/off boolean
int inSetMinMode = false;     // in programming mode for setting the minimum boolean
int inSetMaxMode = false;     // in programming mode for setting the maximum boolean
int maxFlashRate = 100;       // Flash rate for LED STAT2 when inSetMaxMode (ms)
int minFlashRate = 200;       // Flash rate for LED STAT2 when inSetMinMode (ms)
long maxFlashMillis =0;       // time counter for flash rate for inSetMaxMode LED STAT 2
long minFlashMillis =0;       // time counter for flash rate for inSetMinMode LED STAT 2
int maxFlash = HIGH;          // State of LED STAT 2 when inSetMaxMode (toggles HIGH/LOW)
int minFlash = HIGH;          // State of LED STAT 2 when inSetMaxMode (toggles HIGH/LOW)

int setProgModeTime = 1000;   // Amount of time to hold D4 to put things into Programming Mode (setting min/max's)
long setProgModeD4;           // time counter for measuring time D4 held 
int inProgMode = false;       // Programming mode or not boolean 
int progInput = 0;            // Current midi analog input channel we are setting min/max mode for 
int progFlashCount = 0;       // Counter for number of flashes for LED STAT 1 when in programming mode (indicates midi input being programmed)
int progToggle = HIGH;        // State of LED STAT 1 when programming (HIGH/LOW toggle)
long progFlashRate = 100;     // Flash rate for LED STAT2 when in programming mode (ms)
long progFlashPrev = 0;       // time counter for flash rate when in programming mode for LED STAT 1

// The Arduino setup.  
void setup() {
  // Set LED's to outputs
  pinMode(LEDarduino, OUTPUT);
  pinMode(LED1,OUTPUT);
  pinMode(LED2,OUTPUT); 
  // Set Switches to inputs 
  pinMode(D2,INPUT);
  digitalWrite(D2,HIGH);  // Activate internal pullup resistor 
  pinMode(D3,INPUT);
  digitalWrite(D3,HIGH);  // Activate internal pullup resistor 
  pinMode(D4,INPUT); 
  digitalWrite(D4,HIGH);  // Activate internal pullup resistor 
  //  Set MIDI baud rate:
#ifndef DEBUG
  Serial.begin(31250);   // Actual Midi rate
#endif

#ifdef DEBUG
  Serial.begin(9600);  // More convenient for debugging over USB
#endif 

  // A brief little flash of the STAT1/STAT2 LED's to let us know it's booted and ready to go 
  digitalWrite(LED1,LOW);    // Turns on the status LED's
  digitalWrite(LED2,LOW); 
  delay(50);  
  digitalWrite(LED1,HIGH);   // Turns off the status LED's 
  digitalWrite(LED2,HIGH); 
#ifdef DEBUG
  Serial.println("START"); 
#endif 
}

// main program loop
void loop() {

  int toggle=HIGH; 

  int input = LOW;
  int analog = 0; 

  theMillis = millis();   // Current millis setting for comparing debouncing and led flashing times. 

  //--- D2 ----------------------------------------------
  // Pushing D2 will put the unit into "Set Maximum position" mode, LED1 will flash, you set the controller to 
  // position for max value, push D2 again, and that position is recorded as the max controller output position.  
  D2bounce.update(); 
  input=D2bounce.read(); 

  if (input == LOW && D2bounce.fallingEdge()) {    // D2 has just been pushed on this cycle. 
    if (inProgMode == true) {
      if (inSetMaxMode == false)   {
        inSetMaxMode = true; 
#ifdef DEBUG
        Serial.println("Setting Max mode Started");
#endif 
      } 
      else  {
        inSetMaxMode = false; 
        midiAnalogMax[progInput] = analogRead(progInput);

#ifdef DEBUG
        Serial.print("Input "); 
        Serial.print(progInput); 
        Serial.print(" Max is now"); 
        Serial.println(midiAnalogMax[progInput]); 
#endif 

        digitalWrite(LED1,HIGH);  // Turn off LED 
      }  
    } 
  }

  // Handles the flashing of the LED during inSetMaxMode
  if (inSetMaxMode == true)  {
    if (theMillis - maxFlashMillis > maxFlashRate) {
      if (maxFlash == HIGH) 
        maxFlash = LOW;
      else 
        maxFlash = HIGH; 

      maxFlashMillis = theMillis; 
    }
    digitalWrite(LED1,maxFlash); 
  }
  //--- End of D2 Handler -------------------------------

  //--- D3 ----------------------------------------------
  // Pushing D3 will put the unit into "Set Minimum position" mode, LED1 will flash, you set the controller to 
  // position for min value, push D3 again, and that position is recorded as the min controller output position.
  D3bounce.update();  
  input=D3bounce.read(); 

  if (input == LOW && D3bounce.fallingEdge()) { 

    if (inProgMode == true) {
      if (inSetMinMode == false)   {
        inSetMinMode = true; 

#ifdef DEBUG
        Serial.println("Setting Min mode Started");
#endif 

      } 
      else     {
        inSetMinMode = false; 
        midiAnalogMin[progInput] = analogRead(progInput);

#ifdef DEBUG
        Serial.print("Input ");
        Serial.print(progInput); 
        Serial.print(" Min is now"); 
        Serial.println(midiAnalogMin[progInput]); 
#endif

        digitalWrite(LED1,HIGH);  // Turn off LED 
      }
    }
  }

  // Handles the flashing of the LED during inSetMaxMode
  if (inSetMinMode == true)  {
    if (theMillis - minFlashMillis > minFlashRate) {
      if (minFlash == HIGH) 
        minFlash = LOW;
      else 
        minFlash = HIGH; 

      minFlashMillis = theMillis; 
    }
    digitalWrite(LED1,minFlash); 
  }
  //--- End of D3 Handler -------------------------------


  //--- D4 ----------------------------------------------
  // Pushing D4 enables midi control on/off and enter/leaving programming mode 
  D4bounce.update(); 
  input=D4bounce.read(); 

  if (input == LOW && D4bounce.fallingEdge()) {   // Button has just been pushed on this scan, start counting time in setProgModeD4
    setProgModeD4 = theMillis; 
  }

  if (input == HIGH && D4bounce.risingEdge() && (theMillis - setProgModeD4 > setProgModeTime) ) {   // A Release after long press has happened 
    if (inProgMode == true) {
#ifdef DEBUG
      Serial.println("Leaving Prog Mode"); 
#endif
      inProgMode= false; 
    } 
    else {
#ifdef DEBUG
      Serial.println("Entering Prog mode"); 
#endif 
      inProgMode = true; 
      progInput = 0;       // Start programming with first channel every time 
    }
  }



  if (input == HIGH && D4bounce.risingEdge() && (theMillis - setProgModeD4 < setProgModeTime)) {   // A Release after short press has happened
    if (inProgMode == true) {
      progInput++;    // select next midi input for programming  
      if (progInput > input_no) progInput=0;     // wrap around if at last analog input 
#ifdef DEBUG
      Serial.print("Prog channel "); 
      Serial.println(progInput); 
#endif



    } 
    else {   // Not inProgMode, just turn midi on and off 

      if (isOn == false)   {
        isOn = true; 
#ifdef DEBUG
        Serial.println("Midi control ON");
#endif 
        digitalWrite(LED2,LOW);  
      } 
      else     {
        isOn = false; 

#ifdef DEBUG
        Serial.println("Midi Control OFF"); 
#endif 
        digitalWrite(LED2,HIGH);
      }
    }
  }

  // Handles the flashing of the STAT1 LED when in programming mode.  Flashes a number of times 
  // based on what channel is currently being programmed, then a pause, then starts again. 
  if (inProgMode == true)  {
    if (theMillis - progFlashPrev > progFlashRate)  {
      progFlashPrev = theMillis; 
      if (progToggle == HIGH)  {
        progToggle=LOW; 
        progFlashCount++; 
      } 
      else {
        progToggle=HIGH; 
      }

      // with the 2*input_no, then there will always be a series of "blank" states at the end of the 
      // flashing sequence where the LED does not flash, so humans can tell when the "number of flashes indicates what channel"
      // sequence is starting and stopping. 
      if (progFlashCount > 2*input_no) progFlashCount=0;   
      if (progFlashCount <= progInput) {
        digitalWrite(LED2,progToggle);
      } 
      else {
        digitalWrite(LED2,HIGH);     // HIGH is "not lit"
      }

    }    

  }


  //--- End of D4 Handler -------------------------------  





  //---- Midi Loop ------------

  if (isOn==true) {    // Only send midi messages if enabled 
    for(int i=0;i<=input_no;i++){
      input = analogRead(i); 
      // Using "map()" is a lot more convenient than writing a lot of if() blocks and math.    http://www.arduino.cc/en/Reference/Map
      // It also very conveniently works if you "flip" the min/max positions (ie - you like the knobs or pedals to work in the opposite 
      // direction for increasing value and have used the programming mode to set min higher than max) 
      AnalogValue[i] = map(input, midiAnalogMin[i],midiAnalogMax[i],0,127); 
      // Constrain guarantees 0 <= midi <= 127 values are sent  http://www.arduino.cc/en/Reference/Constrain
      AnalogValue[i] = constrain(AnalogValue[i],0,127); 
      // check if value is greater than defined threshold (good for resistive touchpads etc)
      if ( AnalogValue [i]>thresh[i] ) {
        // check if analog input has changed, don't spam output if controller value hasn't changed. 
        // Noisy midi inputs are a pain.   
        if ( AnalogValue[i] != lastAnalogValue[i] ) {
          digitalWrite(LEDarduino,HIGH);                     // light up LED to let you know we're sending data
          midiCC(0xB0, midiCCselect[i], AnalogValue[i]);
          digitalWrite(LEDarduino,LOW);   
          lastAnalogValue[i] = AnalogValue[i];
        }
      }

    }
  }
  //---- Midi Loop ------------


}  // loop() ends



// This function sends a Midi CC.
void midiCC(char CC_data, char c_num, char c_val){

#ifndef DEBUG
  Serial.print(CC_data, BYTE);
  Serial.print(c_num, BYTE);
  Serial.print(c_val, BYTE);
#endif 

#ifdef DEBUG
  Serial.print("MIDI: "); 
  Serial.print(CC_data, HEX);
  Serial.print(" "); 
  Serial.print(c_num, DEC);
  Serial.print(" "); 
  Serial.println(c_val, DEC);
#endif

}









