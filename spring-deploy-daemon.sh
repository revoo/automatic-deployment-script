#!/usr/bin/env bash

# This script will run in the background to continuously deploy the latest version of a Spring JAR that lands in a certain directory while stopping the previously running instance.
# this is not really a daemon process but the intention is for it to be always running even after instance restarts via cron.
# real daemonized proceses aren't attached to a TTY session and have no interactive user. They are standalone processes kicked off by the system.

# this script has been set up as a service with systemd 
# start with systemctl start deploy-daemon.service
# this file is located in /etc/systemd/system

# configure terminal colors
CYAN=$(tput setaf 6)
NORMAL=$(tput sgr0)
UNDERLINE=$(tput smul)
RED=$(tput setaf 1)
comparison_file="comparison-date-file.date"
jar_path="/opt/deploy-daemon/webapp"

printf "\n$(date) -------> Automatic JAR deployment daemon started.\n"
printf "\n$(date) -------> Terminating any existing JAR process..\n"
kill -9 $(pgrep -f jar) 
# use -f for pgreg to match the entire command (e.g. java spring.jar -f will also match the spring or jar rather than just java)
sleep 4

printf "\n$(date) -------> Checking that the JAR directory has the latest JAR prepared.\n"
if [ $(ls -l $jar_path | wc -l) -gt 4 ]; then
	printf "\n$(date) -------> JAR directory has old files - archiving them and keeping the newest JAR.\n"
	cd $jar_path
	# move older files to archive and keep the newest jar
	ls -t --ignore=archive --ignore=config  | xargs -n1 | tail -n +2 | xargs mv -t archive
	cd ..
	# -I option will ignore any patterns that start with archive which is our directory
	# Alternatively, you can use the --ignore=PATTERN flag which is what I decided to use
	# args will split input into lines
	# tail -n +2 will skip the first line since that is the newest one chronologically and the one we want to keep
	# finally xargs will take the input and move the files into our archive directory
	printf "\n$(date) -------> Older JAR files archived.\n"
fi

# store date of current spring jar and then compare it every iteration cycle - if the date is newer then bounce the jar.
# the simplest solution is to just touch a comparison file and then use -nt comparison to check
printf "\n$(date) -------> Creating date comparison file.\n"
touch $comparison_file

# start the server since this is the script start up
printf "\n$(date) -------> Fresh script start - starting Spring Tomcat server for the first time.\n"
printf "\n$(date) -------> Starting new Spring JAR: ${UNDERLINE}$(ls $jar_path/*.jar)${NORMAL}\n"
java -Dspring.config.location=/opt/deploy-daemon/webapp/config/application.properties -jar $jar_path/*.jar &> tomcat-log.txt &
PID=$!
printf "\n$(date) -------> PID of Spring process: ${UNDERLINE}$PID${NORMAL}\n"
printf "\n$(date) -------> Tomcat server running.\n"
printf "\n$(date) -------> Monitoring for JAR file changes...\n"
echo $PID > server.pid

while sleep 20; do
	if [ $(ls -l $jar_path | wc -l) -gt 4 ]; then
		printf "\n$(date) -------> New JAR Landed -> Archiving older JAR file and restart server with new JAR file.\n"
		cd $jar_path
		ls -t --ignore=archive --ignore=config | xargs -n1 | tail -n +2 | xargs mv -t archive
		cd ..
		printf "\n$(date) -------> Older JAR files archived.\n"
	fi
	if [ $comparison_file -nt $jar_path/*.jar ]; then
		printf "$(date) -------> Comparison file is newer than the JAR file - Nothing to be done. Sleeping for a few.\n"
	else 
		printf "\n$(date) -------> ${UNDERLINE}New JAR file detected${NORMAL} - JAR file is newer than date comparison file.\n"
		printf "$(date) -------> Restarting Tomcat server via JAR.\n"
		printf "$(date) -------> Killing process: ${UNDERLINE}$PID${NORMAL}\n"
		# can use killall to shut down all java processes or kill -9 (SIGKILL signal - unblockable) just for the specific PID
		kill -SIGKILL $(cat server.pid)
		sleep 5 
		# verify process is killed by using command line option -0
		kill -0 $PID
		if [ $? -ne 0 ]; then
			printf "$(date) -------> Process: ${UNDERLINE}$PID${NORMAL} killed successfully.\n"
		else 
			printf "$(date) -------> ${RED}ERROR:${NORMAL} process: ${UNDERLINE}$PID${NORMAL} was NOT killed successfully.\n"
		fi
		printf "\n$(date) -------> Starting new Spring JAR: ${UNDERLINE}$(ls $jar_path/*.jar)${NORMAL}\n"
		java -Dspring.config.location=/opt/deploy-daemon/webapp/config/application.properties -jar $jar_path/*.jar &> tomcat-log.txt &
		PID=$!
		printf "\n$(date) -------> PID of Spring process: ${UNDERLINE}$PID${NORMAL}\n"
		printf "\n$(date) -------> Tomcat server running.\n"
		printf "\n$(date) -------> Monitoring for JAR file changes...\n"
		echo $PID > server.pid
		# update comparison file timestamp
		touch $comparison_file
	fi
done
