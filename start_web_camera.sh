#!/bin/bash

ask_yes_no() {
    local prompt="$1"
    local answer
    
    while true; do
        read -p "$prompt (y/n): " answer
        answer=${answer,,}
        
        case "$answer" in
            y|yes|да)
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    done
}


check_no_permissions() {
    local output="$1"
    
    if echo "$output" | grep -qi "no permissions"; then
        return 0  # true - есть ошибка
    else
        return 1  # false - нет ошибки
    fi
}

connection_over_wifi=-1
if ask_yes_no "Do you want to connect over wifi?"; then
    echo "Try to connect..."
    connected=-1
    port=5555
    for i in {100..110}; do
        if adb connect 192.168.0.$i:$port | grep -q "connected to "; then
            connected=1
            echo "Device has been connected"
            break
        fi
    done
    
    if [ $connected -ne 1 ]; then
        echo "Connction over wifi has been fault."
        echo "Connect device by USB. Press Enter to continue"
        read
        ip=""
        while true; do
            ip=$(adb shell ip addr show wlan0 | grep -oP 'inet \K[\d.]+')
            if [ -z "$ip" ]; then
                echo "Подключение не обнаружено. Переподсоедените устройство"
            else
                break
            fi
        done
        
        adb tcpip $port
        echo "You can disconnect usb. Press Enter to continue"
        adb $ip:$port
        if adb $ip:$port | grep -q "connected to "; then
            connected=1
            echo "Device has been connected"
        else
            echo "Connceting failed"
            exit 1
        fi
    fi
fi

output=$(adb devices 2>&1)

# Проверяем наличие устройств
if ! echo "$output" | grep -q "device$"; then
    echo "No devices detectes"
    exit 1
fi

if check_no_permissions "$output"; then
    echo "You have no roots!"
    echo "Try:"
    echo "  1. Reconnect device to ypur PC"
    echo "  2. Restart adb server: adb kill-server && adb start-server"
    echo "  3. Check permissions on device"
    exit 1
fi

if [ -f /dev/video22 ]; then
    echo "Creating virtual video device"
    sudo modprobe v4l2loopback devices=1 video_nr=22 exclusive_caps=1 card_label="Virtual Webcam"
fi

scrcpy --list-cameras

read -p "Enter your camera id: " CAMERA_ID

fps_list=($(scrcpy --list-cameras | grep "camera-id=$CAMERA_ID" | grep -oP 'fps=\[\K[0-9, ]+' | tr ',' ' '))

echo "FPS for camera $CAMERA_ID:"
for i in "${!fps_list[@]}"; do
    echo "$((i)). ${fps_list[$i]}"
done

num=-1
max_value=$((${#fps_list[@]}-1))
while true; do
    read -p "Choose FPS: " num
    if [ $num -ge 0 ] && [ $num -le $max_value ]; then
        break
    fi
    echo "Number is out of range [1-$max_value]"
done
selected=${fps_list[$num]}

if ask_yes_no "Enable window output (default is No)?"; then
    no_window=""
else
    no_window="--no-window"
fi

if ask_yes_no "Enable audio (default is No)?"; then
    no_audio=""
else
    no_audio="--no-audio"
fi

scrcpy --v4l2-sink=/dev/video22 --video-source=camera $no_audio --camera-size=1920x1080 --camera-id=$CAMERA_ID --camera-fps=$selected $no_window --render-driver=opengl