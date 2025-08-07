{pkgs, ...}:
pkgs.writeShellApplication {
  name = "swaylockCheck";
  text = ''
    debug=1
    dryRun=1

    if [[ -z "''${SWAYLOCKCHECK+z}" ]];
    then
    	# TODO: need to know if SWAYLOCKCHECK needs to be explicitly exported (with the export command)
    	# or if -x is enough to do so.
    	if [[ $debug ]]; then
    		echo "SETTING SWAYLOCKCHECK"
    	fi
    	declare -A -x SWAYLOCKCHECK
    	#export SWAYLOCKCHECK
    fi

    _IFS=$IFS
    IFS=$'\n'
    # set grace period to 3 seconds (will change or make it overrideable later)
    lockTimeout=4
    for session in $(loginctl list-sessions --no-legend);
    do
    	ses_num=$(echo "$session" | awk '{print $1}')
    	if [[ $debug ]]; then
    		echo "CHECKING SESSION: $ses_num";
    	fi
    	if [[ $(loginctl show-session "$ses_num" | grep 'LockedHint' | awk -F= '{print $2}') == 'no' ]];
    	then
    		lockTimeCandidate=$(date +%s)
    		if [[ -v "SWAYLOCKCHECK[$ses_num]" ]]; then
    			lockTimeCheck=$((SWAYLOCKCHECK[$ses_num]+lockTimeout))
    			if [[ $lockTimeCheck -lt $lockTimeCandidate ]]; then
    				if [[ $debug ]]; then
    					echo "SWAYLOCK-CHECK: SHOULD BE LOCKING SESSION: $session LAST LOCK:''${SWAYLOCKCHECK[$ses_num]} NEW LOCK: $lockTimeCandidate"
    				fi
    				SWAYLOCKCHECK[$ses_num]=$lockTimeCandidate
    				if ! [[ $dryRun ]]; then
    					loginctl lock-session "$ses_num"
    				fi
    			else
    				if [[ $debug ]]; then
    					echo "SWAYLOCKCHECK: NOT LOCKING, GRACE PERIOD NOT PASSED: LAST LOCK: ''${SWAYLOCKCHECK[$ses_num]} LOCK: $lockTimeCandidate"
    				fi
    			fi
    		else
    			if [[ $debug ]]; then
    				echo "SWAYLOCKCHECK: SHOULD BE LOCKING NEW SESSION: $session NEW LOCK: $lockTimeCandidate"
    			fi

    			SWAYLOCKCHECK[$ses_num]=$lockTimeCandidate
    			if ! [[ $dryRun ]]; then
    				loginctl lock-session "$ses_num"
    			fi
    		fi
    		#echo "SWAYLOCK-CHECK:LOCKING: locking session $ses_num"
    		#loginctl lock-session $ses_num
    		# need to insert
    	else
    		echo "SWAYLOCK-CHECK: session $ses_num is already locked"
    	fi
    done
    IFS=$_IFS
  '';
}
