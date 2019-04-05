#!/bin/bash
. /app/scripts/load_env_sshkey.sh

if [[ -z "${THRESHOLD_DATE_FOR_FILE_ACCEPTANCE}" ]]; then
  echo "THRESHOLD_DATE_FOR_FILE_ACCEPTANCE should be set"
  exit 1
fi

if [[ -z "${TRUSTED_SETUP_TURN}" ]]; then
  echo "TRUSTED_SETUP_TURN should be set"
  exit 1
fi

set -e 

NEWEST_CONTRIBUTION=`lftp sftp://"$SSH_USER":@"$SFTP_ADDRESS" -e "set sftp:connect-program \"ssh -a -x -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa_worker\"; find -l | grep \"response$\" | sort -k4 | tail -1; bye"`
NEWEST_CONTRIBUTION_DATE=`echo "$NEWEST_CONTRIBUTION" | awk '{print $4 $5}' | sed 's/[^0-9]*//g'`
NEWEST_CONTRIBUTION_NAME=`echo "$NEWEST_CONTRIBUTION" | awk '{print $6}'`
NEWEST_CONTRIBUTION_NAME=${NEWEST_CONTRIBUTION_NAME:2}
if [ $NEWEST_CONTRIBUTION_DATE -gt $THRESHOLD_DATE_FOR_FILE_ACCEPTANCE ]; then
				
	echo "current newest contribution is $NEWEST_CONTRIBUTION_NAME with the time $NEWEST_CONTRIBUTION_DATE"

	#safe date of newest contribution so that files are not verified twice
	THRESHOLD_DATE_FOR_FILE_ACCEPTANCE=$NEWEST_CONTRIBUTION_DATE #used for easy testing with source command
	sed -i "s/export THRESHOLD_DATE_FOR_FILE_ACCEPTANCE=.*/export THRESHOLD_DATE_FOR_FILE_ACCEPTANCE=$THRESHOLD_DATE_FOR_FILE_ACCEPTANCE/g" /app/variables.sh

	#If a new contribution is found, do verification and preparation for next round
	cd /app/
	echo "starting download; this could take a while..."
	$connect_to_sftp_server:$NEWEST_CONTRIBUTION_NAME /app/.

	echo "verifying the submission; this could take a while..."
	if [[ ! -z "${CONSTRAINED}" ]]; then
		set +e
		cargo run --release --bin verify_transform_constrained
		if [ $? -eq 0 ]; then
		    VERIFIED="true"
		    echo Verification successful
		else
			VERIFIED="false"
		    echo Verification failed
		fi
		set -e
	else
		set +e
		cargo run --release --bin verify_transform
		if [ $? -eq 0 ]; then
		    VERIFIED="true"
		    echo Verification successful
		else
			VERIFIED="false"
		    echo Verification failed
		fi
		set -e
	fi

	if [[ "$VERIFIED" = "true" ]]; then
		echo "uploading to ftp server and documentation; this could take a while..."
		mv new_challenge challenge
		mv response "response-$TRUSTED_SETUP_TURN"
		
		#upload new challenge file for next candiate
		echo "put challenge" | $connect_to_sftp_server:challenges

		#document response from previous participant
		echo "put response-$TRUSTED_SETUP_TURN" | $connect_to_sftp_server:challenges

		#document new challenge file
		TIME=$(date +%s.%N)
		cp challenge "challenge-$TIME"
		echo "put challenge-$TIME" | $connect_to_sftp_server:challenges


		#safe new variables for next execution
		TRUSTED_SETUP_TURN=$((TRUSTED_SETUP_TURN + 1)) #used for easy testing with source command
		sed -i "s/export TRUSTED_SETUP_TURN=.*/export TRUSTED_SETUP_TURN=$TRUSTED_SETUP_TURN/g" /app/variables.sh
		
		#Post a message in Gitter:
		MESSAGE="The submission of $NEWEST_CONTRIBUTION was successful. The new challenge for the $TRUSTED_SETUP_TURN -th contributor has been uploaded. If you want to be the next contributor, let us know in the chat. Your challenge would be ready here: sftp:trusted-setup.staging.gnosisdev.com:challenges"
		. /app/scripts/send_msg_to_gitter.sh "$MESSAGE"
	fi
else
	echo "Newest contribution was created at $NEWEST_CONTRIBUTION_DATE and is not newer than $THRESHOLD_DATE_FOR_FILE_ACCEPTANCE"
fi


