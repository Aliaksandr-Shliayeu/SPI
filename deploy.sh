#!/bin/bash

#make sure you are in right directory
# pushd ~/SPI

#Menu Display Name
#[CONTAINER NAME]="MENU Text"
declare -A cont_array=(
	[bazarr]="Bazarr"
	[bitwardenrs]="Bitwardenrs"
	[deluge]="Deluge - Torrent Client"
	[doublecommander]="Doublecommander"
	[emby]="Emby - Media manager like Plex"
	[embystat]="EmbyStat - Statistics for Emby"
	[heimdall]="Heimdall"
	[jackett]="Jackett"
	[jellyfin]="JellyFin - Media manager no license needed"
	[lidarr]="Lidarr"
	[nginx]="Ngnix - Web Server"
	[nzbget]="NZBGet - Usenet groups client"
	[pihole]="Pi-Hole - Private DNS sinkhole"
	[plex]="Plex - Media manager"
	[portainer]="Portainer - GUI Docker Manager"
	[pwndrop]="Pwndrop"
	[qbittorrent]="qBittorrent - Torrent Client"
	[radarr]="Radarr"
	[sabznbd]="SABznbd - Usenet groups client"
	[sonarr]="Sonarr"
	[torrserver]="Torrserver"
	[transmission]="Transmission - Torrent Client"
	[tvheadend]="TVheadend - TV streaming server"
	[vpn]="vpn-client OpenVPN Gateway"
)

# CONTAINER keys
declare -a armhf_keys=(
	"bazarr"
	"bitwardenrs"
	"deluge"
	"doublecommander"
	"emby"
	"embystat"
	"heimdall"
	"jackett"
	"jellyfin"
	"lidarr"
	"nginx"
	"nzbget"
	"pihole"
	"plex"
	"portainer"
	"pwndrop"
	"qbittorrent"
	"radarr"
	"sabznbd"
	"sonarr"
	"torrserver"
	"transmission"
	"tvheadend"
	"vpn"
)

sys_arch=$(uname -m)

#timezones
timezones() {

	env_file=$1
	TZ=$(cat /etc/timezone)

	#test TimeZone=
	[ $(grep -c "TZ=" $env_file) -ne 0 ] && sed -i "/TZ=/c\TZ=$TZ" $env_file

}

# This function creates the volumes, services and backup directories.
# It then assisgns the current user to the ACL to give full read write access
docker_setfacl() {
	[ -d /storage/services ] || mkdir /storage/services
	[ -d /storage/config ] || mkdir /storage/config
	[ -d /storage/SPIBackups ] || mkdir /storage/SPIBackups


	#give current user rwx on the volumes and backups
	[ $(getfacl /storage/config | grep -c "default:user:$USER") -eq 0 ] && sudo setfacl -Rdm u:$USER:rwx /storage/config
	[ $(getfacl /storage/SPIBackups | grep -c "default:user:$USER") -eq 0 ] && sudo setfacl -Rdm u:$USER:rwx /storage/SPIBackups

	cat << EOF | sudo tee -a /storage/config/npm-config.json
{
  "database": {
    "engine": "mysql",
    "host": "db",
    "name": "npm",
    "user": "npm",
    "password": "npm",
    "port": 3306
  }
}
EOF

}

#future function add password in build phase
password_dialog() {
	while [[ "$passphrase" != "$passphrase_repeat" || ${#passphrase} -lt 8 ]]; do

		passphrase=$(whiptail --passwordbox "${passphrase_invalid_message}Please enter the passphrase (8 chars min.):" 20 78 3>&1 1>&2 2>&3)
		passphrase_repeat=$(whiptail --passwordbox "Please repeat the passphrase:" 20 78 3>&1 1>&2 2>&3)
		passphrase_invalid_message="Passphrase too short, or not matching! "
	done
	echo $passphrase
}
#test=$( password_dialog )

function command_exists() {
	command -v "$@" >/dev/null 2>&1
}

#function copies the template yml file to the local service folder and appends to the docker-compose.yml file
function yml_builder() {

	service="services/$1/service.yml"

	[ -d /storage/services/ ] || mkdir /storage/services/

		if [ -d /storage/services/$1 ]; then
			#directory already exists prompt user to overwrite
			sevice_overwrite=$(whiptail --radiolist --title "Deployment Option" --notags \
				"$1 was already created before, use [SPACEBAR] to select redeployment configuation" 20 78 12 \
				"none" "Use recent config" "ON" \
				"env" "Preserve Environment and Config files" "OFF" \
				"full" "Pull config from template" "OFF" \
				3>&1 1>&2 2>&3)

			case $sevice_overwrite in

			"full")
				echo "...pulled full $1 from template"
				rsync -a -q .templates/$1/ services/$1/ --exclude 'build.sh'
				;;
			"env")
				echo "...pulled $1 excluding env file"
				rsync -a -q .templates/$1/ services/$1/ --exclude 'build.sh' --exclude '$1.env' --exclude '*.conf'
				;;
			"none")
				echo "...$1 service not overwritten"
				;;

			esac

		else
			mkdir /storage/services/$1
			echo "...pulled full $1 from template"
			rsync -a -q .templates/$1/ services/$1/ --exclude 'build.sh'
		fi


	#if an env file exists check for timezone
	[ -f "/storage/services/$1/$1.env" ] && timezones /storage/services/$1/$1.env

	#add new line then append service
	echo "" >>docker-compose.yml
	cat $service >>docker-compose.yml

	#test for post build
	if [ -f /storage/.templates/$1/build.sh ]; then
		chmod +x /storage/.templates/$1/build.sh
		bash /storage/.templates/$1/build.sh
	fi

	#test for directoryfix.sh
	if [ -f /storage/.templates/$1/directoryfix.sh ]; then
		chmod +x /storage/.templates/$1/directoryfix.sh
		echo "...Running directoryfix.sh on $1"
		bash /storage/.templates/$1/directoryfix.sh
	fi

	#make sure terminal.sh is executable
	[ -f /storage/services/$1/terminal.sh ] && chmod +x /storage/services/$1/terminal.sh

}
#---------------------------------------------------------------------------------------------------
# Menu system starts here
# Display main menu
mainmenu_selection=$(whiptail --title "Main Menu" --menu --notags \
	"" 20 78 12 -- \
	"install" "Install Docker" \
	"build" "Build SPI Stack" \
	"commands" "Docker commands" \
	"misc" "Miscellaneous commands" \
	"update" "Update SPI Stack" \
	"backup" "Backup and Restore SPI" \
	3>&1 1>&2 2>&3)
# "backup" "Backup SPI - (external scripts)" \


case $mainmenu_selection in
#MAINMENU Install docker  ------------------------------------------------------------
"install")
	#sudo apt update && sudo apt upgrade -y ;;

	if command_exists docker; then
		echo -e "     "
		echo -e "\e[30;48;5;82m    Docker already installed\e[0m"
	else

		echo -e "     "
		echo -e "\e[33;1m    Instaling Docker - please wait\e[0m"
		curl -fsSL https://get.docker.com | sh &> /dev/null
		sudo usermod -aG docker $USER &> /dev/null
		echo -e "\e[32;1m    Docker Installed\e[0m"

	fi

	if command_exists docker-compose; then
		echo -e "\e[30;48;5;82m   Docker-compose already installed\e[0m"
	else
		echo -e "\e[33;1m    Instaling docker-compose - please wait\e[0m"
		sudo apt install -y docker-compose &> /dev/null
		echo -e "\e[32;1m    Docker-compose Installed\e[0m"
		echo -e "     "
	fi

	if (whiptail --title "Restart Required" --yesno "It is recommended that you restart your device now. User (pi) was added to the (docker) user group for this to take effect logout and log back in or reboot. Select yes to do so now" 20 78); then
		sudo reboot
	fi
	;;
	#MAINMENU Build stack ------------------------------------------------------------
"build")

	title=$'Container Selection'
	message=$'Use the [SPACEBAR] to select which containers you would like to use'
	entry_options=()

	#check architecture and display appropriate menu
	if [ $(echo "$sys_arch" | grep -c "arm") ]; then
		keylist=("${armhf_keys[@]}")
	else
		echo "your architecture is not supported yet"
		exit
	fi

	#loop through the array of descriptions
	for index in "${keylist[@]}"; do
		entry_options+=("$index")
		entry_options+=("${cont_array[$index]}")

		#check selection
		if [ -f /storage/services/selection.txt ]; then
			[ $(grep "$index" /storage/services/selection.txt) ] && entry_options+=("ON") || entry_options+=("OFF")
		else
			entry_options+=("OFF")
		fi
	done

	container_selection=$(whiptail --title "$title" --notags --separate-output --checklist \
		"$message" 20 78 12 -- "${entry_options[@]}" 3>&1 1>&2 2>&3)

	mapfile -t containers <<<"$container_selection"

	#if no container is selected then dont overwrite the docker-compose.yml file
	if [ -n "$container_selection" ]; then
		touch docker-compose.yml
		echo "version: '3'" >docker-compose.yml
		echo "services:" >>docker-compose.yml

		#set the ACL for the stack
		#docker_setfacl

		# store last sellection
		[ -f /storage/services/selection.txt ] && rm /storage/services/selection.txt
		#first run service directory wont exist
		[ -d /storage/services ] || mkdir services
		touch /storage/services/selection.txt
		#Run yml_builder of all selected containers
		for container in "${containers[@]}"; do
			echo "Adding $container container"
			yml_builder "$container"
			echo "$container" >>/storage/services/selection.txt
		done

		# add custom containers
		if [ -f /storage/services/custom.txt ]; then
			if (whiptail --title "Custom Container detected" --yesno "custom.txt has been detected do you want to add these containers to the stack?" 20 78); then
				mapfile -t containers <<<$(cat /storage/services/custom.txt)
				for container in "${containers[@]}"; do
					echo "Adding $container container"
					yml_builder "$container"
				done
			fi
		fi

		echo "docker-compose successfully created"
		echo -e "run \e[104;1mdocker-compose up -d\e[0m to start the stack"
	else

		echo "Build cancelled"

	fi
	;;
	#MAINMENU Docker commands -----------------------------------------------------------
"commands")

	docker_selection=$(
		whiptail --title "Docker commands" --menu --notags \
			"Shortcut to common docker commands" 20 78 12 -- \
			"aliases" "Add SPI_up and SPI_down aliases" \
			"start" "Start stack" \
			"restart" "Restart stack" \
			"stop" "Stop stack" \
			"stop_all" "Stop any running container regardless of stack" \
			"pull" "Update all containers" \
			"prune_volumes" "Delete all stopped containers and docker volumes" \
			"prune_images" "Delete all images not associated with container" \
			3>&1 1>&2 2>&3
	)

	case $docker_selection in
	"start") /storage/scripts/start.sh ;;
	"stop") /storage/scripts/stop.sh ;;
	"stop_all") /storage/scripts/stop-all.sh ;;
	"restart") /storage/scripts/restart.sh ;;
	"pull") /storage/scripts/update.sh ;;
	"prune_volumes") /storage/scripts/prune-volumes.sh ;;
	"prune_images") /storage/scripts/prune-images.sh ;;
	"aliases")
		touch ~/.bash_aliases
		if [ $(grep -c 'SPI' ~/.bash_aliases) -eq 0 ]; then
			echo ". ~/SPI/.bash_aliases" >>~/.bash_aliases
			echo "added aliases"
		else
			echo "aliases already added"
		fi
		source ~/.bashrc
		echo "aliases will be available after a reboot"
		;;
	esac
	;;
	#Backup menu ---------------------------------------------------------------------
"backup")
	backup_selection=$(
		whiptail --title "Backup and Restore SPI" --menu --notags \
			"While configuring rclone to work with Google Drive (option 12), make sure you give a folder name of (gdrive). Be carefull when you restore from backup. All containers will be stop and their settings overwritten with what is in your last backup file. All containers will start automatically after restore is done." 20 78 12 -- \
			"rclone" "Install rclone and configure (gdrive) for backup" \
			"rclone_backup" "Backup SPI" \
			"rclone_restore" "Restore SPI" \
			3>&1 1>&2 2>&3
	)

	case $backup_selection in
	"rclone")
    if dpkg-query -W rclone | grep -w 'rclone' &> /dev/null && rclone listremotes | grep -w 'gdrive:' >> /dev/null ; then

        #rclone installed and gdrive exist
			echo -e "\e[32m=====================================================================================\e[0m"
			echo -e "\e[36;1m    rclone installed and gdrive configured, go to Backup or Restore \e[0m"
   		    echo -e "\e[32m=====================================================================================\e[0m"
	else
		sudo apt install -y rclone
			echo -e "\e[32m=====================================================================================\e[0m"
			echo -e "     Please run \e[32;1mrclone config\e[0m and create remote \e[34;1m(gdrive)\e[0m for backup   "
			echo -e "     "
			echo -e "     Do as folows:"
			echo -e "      [n] [gdrive] [12] [Enter] [Enter] [1] [Enter] [Enter] [n] [n]"
			echo -e "      [Copy link from SSH console and paste it into the browser]"
			echo -e "      [Login to your google account]"
			echo -e "      [Copy token from Google and paste it into the SSH console]"
			echo -e "      [n] [y] [q]"
			echo -e "\e[32m=====================================================================================\e[0m"
	fi
		;;

	"rclone_backup") /storage/scripts/rclone_backup.sh ;;
	"rclone_restore") /storage/scripts/rclone_restore.sh ;;

	esac
	;;

	#MAINMENU Misc commands------------------------------------------------------------
"misc")
	misc_sellection=$(
		whiptail --title "Miscellaneous Commands" --menu --notags \
			"Some helpful commands" 20 78 12 -- \
			"swap" "Disable swap by uninstalling swapfile" \
			"swappiness" "Disable swap by setting swappiness to 0" \
			"log2ram" "install log2ram to decrease load on sd card, moves /var/log into ram" \
			3>&1 1>&2 2>&3
	)

	case $misc_sellection in
	"swap")
		sudo dphys-swapfile swapoff
		sudo dphys-swapfile uninstall
		sudo update-rc.d dphys-swapfile remove
		sudo systemctl disable dphys-swapfile
		#sudo apt-get remove dphys-swapfile
		echo "Swap file has been removed"
		;;
	"swappiness")
		if [ $(grep -c swappiness /etc/sysctl.conf) -eq 0 ]; then
			echo "vm.swappiness=0" | sudo tee -a /etc/sysctl.conf
			echo "updated /etc/sysctl.conf with vm.swappiness=0"
		else
			sudo sed -i "/vm.swappiness/c\vm.swappiness=0" /etc/sysctl.conf
			echo "vm.swappiness found in /etc/sysctl.conf update to 0"
		fi

		sudo sysctl vm.swappiness=0
		echo "set swappiness to 0 for immediate effect"
		;;
	"log2ram")
		if [ ! -d ~/log2ram ]; then
			git clone https://github.com/azlux/log2ram.git ~/log2ram
			chmod +x ~/log2ram/install.sh
			pushd ~/log2ram && sudo /storage/install.sh
			popd
		else
			echo "log2ram already installed"
		fi
		;;
	esac
	;;


"update")
	echo "Pulling latest project file from Github.com ---------------------------------------------"
	git pull origin main
	echo "git status ------------------------------------------------------------------------------"
	git status
	;;

*) ;;

esac
