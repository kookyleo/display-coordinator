# Display Coordinator for Dual Mac

## Background
I have two mac with 27" displays on my desk, which is great for productivity. However, I don't need both screens active simultaneously as they serve different purposes. In fact, having both screens lit up can be distracting - the non-focused screen becomes like a desk lamp shining directly at your eyes. That's why I created these scripts.

The goal is to automatically turn off one screen when the other is activated (while it can be configured bidirectionally, I only needed it one-way for my setup).

## How It Works
Two programs work together to achieve this:

1. **Checker4ScreenBrightnessThenSend**
   - Continuously monitors screen brightness
   - Sends a specific message to another machine when screen is activated

2. **ReceiverThenSleepDisplay**
   - Listens on a specified port
   - Turns off the screen when it receives the designated message

By combining these programs, we can achieve the desired screen control behavior.

## Limitations
- The programs are designed for my specific hardware/software environment and requirements
- Different macOS versions might generate warnings or errors
- External display state detection might vary depending on the hardware
- Likely requires case-by-case debugging as these are utility scripts rather than a polished product

## Installation and Usage reference

### Clone and Navigate
```bash
git clone https://github.com/kookyleo/display-coordinator.git
cd display-coordinator
```

### Install ReceiverThenSleepDisplay
```bash
# Compile and install
swiftc ReceiverThenSleepDisplay.swift
cp ReceiverThenSleepDisplay /usr/local/bin/
chmod 755 /usr/local/bin/ReceiverThenSleepDisplay

# Configure and setup LaunchAgent
LISTEN_PORT=12345
sed -i '' "s/LISTEN_PORT/$LISTEN_PORT/g" ReceiverThenSleepDisplay.plist
cp ReceiverThenSleepDisplay.plist ~/Library/LaunchAgents/

# Load the service
sudo launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/ReceiverThenSleepDisplay.plist
sudo launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ReceiverThenSleepDisplay.plist
launchctl list | grep -i ReceiverThenSleepDisplay
```

### Install Checker4ScreenBrightnessThenSend
```bash
# Compile and install
swiftc Checker4ScreenBrightnessThenSend.swift
cp Checker4ScreenBrightnessThenSend /usr/local/bin/
chmod 755 /usr/local/bin/Checker4ScreenBrightnessThenSend

# Configure and setup LaunchAgent
TARGET_HOST=1.2.3.4
TARGET_PORT=12345
sed -i '' "s/TARGET_HOST/$TARGET_HOST/g" Checker4ScreenBrightnessThenSend.plist
sed -i '' "s/TARGET_PORT/$TARGET_PORT/g" Checker4ScreenBrightnessThenSend.plist
cp Checker4ScreenBrightnessThenSend.plist ~/Library/LaunchAgents/

# Load the service
sudo launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/Checker4ScreenBrightnessThenSend.plist
sudo launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/Checker4ScreenBrightnessThenSend.plist
sudo launchctl list | grep -i Checker4ScreenBrightnessThenSend
```

## Customization
Both programs support command-line arguments for flexible configuration. Just Check the files for details.
