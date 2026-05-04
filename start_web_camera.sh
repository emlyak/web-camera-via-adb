!/bin/bash

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

show_help() {
    echo "Usage: $0"
    echo "A small script that simplifies setting up an Android smartphone as a webcam."
    echo "Used adb as instrument for getting access to camera"
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) 
            show_help $0
            exit 0 ;;
    esac
    shift
done


declare selected_id

search_by_wifi() {
    echo "------------------------------------------------------"
    echo "Try to connect..."
    connected=-1
    port=5555
    count=0
    for i in {100..110}; do
        if adb connect 192.168.0.$i:$port | grep -q "^connected to "; then
            connected=1
            ((count++))
        fi
    done

    if [ $count -eq 0 ]; then
        echo "Device not found"
        echo "Connect device by USB. Press Enter to continue"
        read
        ip=""
        while true; do
            ip=$(adb shell ip addr show wlan0 | grep -oP 'inet \K[\d.]+')
            if [ -z "$ip" ]; then
                echo "Device not detected. Reconnect usb"
            else
                break
            fi
        done
        
        adb tcpip $port
        echo "You can disconnect usb. Press Enter to continue"
        adb $ip:$port
        if adb $ip:$port | grep -q "connected to "; then
            ((count++))
        else
            echo "Connceting failed"
            exit 1
        fi
    fi
    echo "$count devices found and connected"
    choose_device
}

choose_device() {
    output=$(adb devices -l 2>&1)

    declare -a device_ids
    declare -a device_models

    # Парсим вывод
    while IFS= read -r line; do
        # Пропускаем пустые строки и заголовок
        if [[ -z "$line" ]] || [[ "$line" == "List of devices attached" ]]; then
            continue
        fi
        
        # Извлекаем ID устройства и модель
        if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+device[[:space:]]+.*model:([^[:space:]]+) ]]; then
            device_id="${BASH_REMATCH[1]}"
            model="${BASH_REMATCH[2]}"
            
            device_ids+=("$device_id")
            device_models+=("$model")
        fi
    done <<< "$output"

    # Проверяем, есть ли устройства
    if [ ${#device_ids[@]} -eq 0 ]; then
        echo "No devices detectes"
        exit 1
    fi

    # Выводим компактный список
    echo "------------------------------------------------------"
    echo "Detected devices:"
    echo "  0. Start searching via wifi"
    for i in "${!device_ids[@]}"; do
        echo "  $((i+1)). ${device_ids[$i]} ${device_models[$i]}"
    done

    # Запрашиваем выбор
    while true; do
        read -p "Choose device [0-$((${#device_ids[@]}))]: " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#device_ids[@]} ]; then
            index=$(($choice-1))
            selected_id="${device_ids[$index]}"
            selected_model="${device_models[$index]}"
            echo "Selected device: $selected_id"
            break
        else
            if [ $choice -eq 0 ]; then
                search_by_wifi
            fi
            echo "Number is out of range [0-${#device_ids[@]}]"
        fi
    done
}

choose_device

if [ -f /dev/video22 ]; then
    echo "Creating virtual video device..."
    sudo modprobe v4l2loopback devices=1 video_nr=22 exclusive_caps=1 card_label="Virtual Webcam"
fi

echo "------------------------------------------------------"
scrcpy --list-cameras -s $selected_id

read -p "Enter your camera id: " CAMERA_ID

echo "------------------------------------------------------"
fps_list=($(scrcpy --list-cameras -s $selected_id | grep "camera-id=$CAMERA_ID" | grep -oP 'fps=\[\K[0-9, ]+' | tr ',' ' '))
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

read -p "Additional flags (if you know what are you doing): " additional_flags

echo "------------------------------------------------------"

scrcpy --v4l2-sink=/dev/video22 --video-source=camera $no_audio $no_window -s $selected_id --camera-size=1920x1080 --camera-id=$CAMERA_ID --camera-fps=$selected --render-driver=opengl $additional_flags