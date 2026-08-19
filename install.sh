#!/usr/bin/env bash

# Строгий режим: падать при любых ошибках
set -euo pipefail

echo "==============================================="
echo " Запуск универсального инсталлятора MikroTik   "
echo "==============================================="

# 1. Функция автоматической установки Zenity (GUI движка)
ensure_zenity() {
    if ! command -v zenity &> /dev/null; then
        echo "[!] Zenity не найден. Автоматическая установка..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y -qq zenity
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y -q zenity
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm --noprogressbar zenity
        else
            echo "Ошибка: Пакетный менеджер не поддерживается. Установите zenity вручную."
            exit 1
        fi
    fi
}
ensure_zenity

# 2. Скачивание netinstall-cli, если его еще нет в папке
if [ ! -f "./netinstall-cli" ]; then
    (
        echo "10" ; echo "# Подключение к серверам MikroTik..."
        # Скачиваем официальную стабильную CLI утилиту x86_64
        curl -L "https://mikrotik.com" -o netinstall.tar.gz
        
        echo "60" ; echo "# Распаковка компонентов..."
        tar -xzf netinstall.tar.gz netinstall-cli
        rm -f netinstall.tar.gz
        chmod +x netinstall-cli
        
        echo "100" ; echo "# Утилита готова к работе!"
    ) | zenity --progress --title="Подготовка Netinstall" --auto-close --no-cancel --width=400
fi

# 3. GUI: Выбор сетевого интерфейса
IFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo")
CHOSEN_IFACE=$(echo "$IFACES" | zenity --list --title="Шаг 1: Сетевая карта" \
    --column="Выберите интерфейс, к которому подключен MikroTik" --width=450 --height=250)

if [ -z "$CHOSEN_IFACE" ]; then exit 0; fi

# 4. GUI: Ввод временного IP для роутера
CLIENT_IP=$(zenity --entry --title="Шаг 2: IP-адрес Netboot" \
    --text="Введите IP, который Netinstall временно выдаст роутеру:" \
    --entry-text="192.168.88.1")

if [ -z "$CLIENT_IP" ]; then exit 0; fi

# 5. GUI: Выбор файла прошивки RouterOS
NPK_FILE=$(zenity --file-selection --title="Шаг 3: Выберите файл прошивки (.npk)" \
    --file-filter="Пакеты MikroTik (*.npk) | *.npk")

if [ -z "$NPK_FILE" ]; then exit 0; fi

# 6. GUI: Опции очистки конфигурации
FLAGS_CHOICE=$(zenity --list --checklist --title="Шаг 4: Опции прошивки" \
    --column="Выбор" --column="Флаг" --column="Описание" \
    FALSE "-r" "Сбросить настройки на заводские" \
    FALSE "-e" "Полностью пустая конфигурация (без IP)" \
    --width=500 --height=220)

EXTRA_FLAGS=""
if [[ "$FLAGS_CHOICE" == *"-r"* ]]; then EXTRA_FLAGS="$EXTRA_FLAGS -r"; fi
if [[ "$FLAGS_CHOICE" == *"-e"* ]]; then EXTRA_FLAGS="$EXTRA_FLAGS -e"; fi

# 7. GUI: Запрос пароля sudo (необходим для работы с сокетами Etherboot)
PASSWORD=$(zenity --password --title="Требуются права суперпользователя")
if [ -z "$PASSWORD" ]; then
    zenity --error --text="Ошибка: Без прав sudo прошивка невозможна."
    exit 1
fi

# 8. Инструкция перед стартом
zenity --info --text="ИНСТРУКЦИЯ:\n1. Выключите питание MikroTik.\n2. Зажмите кнопку Reset.\n3. Включите питание, удерживая Reset.\n4. Отпустите кнопку, когда устройство появится в режиме Etherboot.\n\nНажмите ОК для начала ожидания устройства." --width=500

# 9. Запуск прошивки с выводом лога прямо в GUI-окно
echo "$PASSWORD" | sudo -S ./netinstall-cli $EXTRA_FLAGS -a "$CLIENT_IP" "$NPK_FILE" 2>&1 | \
    zenity --text-info --title="Лог прошивки MikroTik" --width=700 --height=450 --autoscroll

zenity --info --text="Процесс завершен. Проверьте текстовое окно выше на наличие ошибок." --width=400
