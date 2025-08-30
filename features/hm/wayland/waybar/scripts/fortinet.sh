#!/usr/bin/env bash

if [[ $1 == "print" ]]; then
	server_name=$(cat /tmp/vpn_server)
	if [[ -z $(pgrep openfortivpn) ]]; then
		echo "{\"text\":\"\",\"alt\":\"Recording\",\"tooltip\":\"tooltip\",\"class\":\"disconnected\"}"
	else
		echo "{\"text\":\" <span font='FluentUI-Filed-Monochrome 14'  color='#ff0000'></span> <span  rise='3000'>""${server_name}" " </span>\",\"alt\":\"Recording\",\"tooltip\":\"tooltip\",\"class\":\"record\"}"
	fi
	# {"text": "$text", "alt": "$alt", "tooltip": "$tooltip", "class": "$class", "percentage": $percentage }
	exit 0
# fi

elif [[ $1 == "connect" ]]; then
	echo "connected" >/tmp/vpn_server
	sleep 2
	pkill -RTMIN+8 waybar
	some_connect_command &
	disown
elif [[ $1 == "disconnect" ]]; then
	killall -9 openfortivpn
	while [ -n "$(pgrep -x openfortivpn)" ]; do wait; done
	pkill -RTMIN+8 waybar
fi
