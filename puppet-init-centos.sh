#!/bin/bash
#puppet-init-centos.sh

function colorize() {
    local color=$(echo $1 | cut -f2 -d=)

    case $color in
        red)
            local color_code='\033[38;5;196m'
            ;;
        green)
            local color_code='\033[38;5;2m'
            ;;
        blue)
            local color_code='\033[38;5;75m'
            ;;
        reset)
            local color_code='\033[0m'
            ;;
        *)
            local color_code='\033[0m'
            ;;
    esac

    echo -ne $color_code
}

function colorize_err() {
    while IFS='' read LINE; do
        colorize --color=red
        echo -e "$LINE" >&2
        tput sgr0
  done
}

function colorize_question() {
    while IFS='' read LINE; do
        colorize --color=blue
        echo -e "-Q| $LINE"
        tput sgr0
    done
}

function colorize_highlight() {
    while IFS='' read LINE; do
        colorize --color=green
        echo -e "$LINE"
        tput sgr0
    done
}

function prompt_yes() {
    while true; do
        read -n 1 reply
        echo
        case $reply in
            [yY])
                return 0
                ;;
            [nN])
                return 1
                ;;
            *)
                echo "Wrong answer :)" | colorize_err
                ;;
        esac
    done
}

#set constants
declare -r CONFIG_SELINUX='/etc/selinux/config'
declare -r CONFIG_NETWORK='/etc/sysconfig/network'
declare -r CONFIG_PUPPET='/etc/puppetlabs/puppet/puppet.conf'

#detect Centos major version and setup right Puppet Labs repository
declare -r CENTOS_MAJOR_VERSION=$(/bin/rpm -q --queryformat '%{VERSION}' centos-release)
case $CENTOS_MAJOR_VERSION in
    6)
        declare -r PUPPET_REPO_URL='https://yum.puppetlabs.com/puppetlabs-release-pc1-el-6.noarch.rpm'
        ;;
    7)
        declare -r PUPPET_REPO_URL='https://yum.puppetlabs.com/puppetlabs-release-pc1-el-7.noarch.rpm'
        ;;
    *)
        echo "This script provides support only for Centos major version 6 and 7." | colorize_err
        exit 1
        ;;
esac

#check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root" | colorize_err
    exit 1
fi

#check, if SELinux is disabled
if ! /bin/grep -E ^SELINUX=disabled$ $CONFIG_SELINUX 1>/dev/null; then
    echo "SELinux enabled!" | colorize_err
    echo "Do you want disable SELinux [y/n]?" | colorize_question 1>&2
    if prompt_yes; then
        /bin/sed -E -i 's/^SELINUX=[a-z]*$/SELINUX=disabled/g' $CONFIG_SELINUX
        echo "SELinux has been disabled." 
        echo "Please reboot your system and run this script again."
        exit 0
    else
        echo "Sorry, script can continue only with disabled SELinux!" | colorize_err
        exit 1
    fi
fi

#install Puppet stufs
if ! /usr/bin/which puppet 1>/dev/null 2>&1; then
    
    #install Puppet Labs repo
    if ! /usr/bin/yum list installed | /bin/grep puppetlabs-release 1>/dev/null; then
        echo "Installing Puppet Labs Yum repository..."
        rpm -ivh $PUPPET_REPO_URL
        if [ $? -ne 0 ]; then
            echo "Error installing Puppet Labs repository!" | colorize_err
            exit 1
        fi
    fi

    #install Puppet agent
    echo "Installing Puppet agent..."
    /usr/bin/yum install -y puppet
    if [ $? -ne 0 ]; then
        echo "Error installing Puppet Agent!" | colorize_err
        exit 1
    fi
    echo
fi

#check and set hostname
function change_hostname() {
    while true; do
        echo "Set new hostname:" | colorize_question 1>&2
        read new_hostname

        if [ -z "$new_hostname" ]; then
            echo "Empty hostname!" | colorize_err
        else
            /bin/hostname $new_hostname
            /bin/sed -E -i "s/^HOSTNAME=.*$/HOSTNAME=$new_hostname/g" $CONFIG_NETWORK
            break
        fi
    done
}

echo -n "Your current hostname is "
echo $(hostname) | colorize_highlight
echo "Do you want to change hostname [y/n]?" | colorize_question 1>&2 
if prompt_yes; then
    change_hostname
fi
echo

#set or replace Puppet server
function get_puppet_server() {
    local server=$(/bin/grep -E "^[[:space:]]*server[[:space:]]?=[[:space:]]?.*$" $CONFIG_PUPPET)

    if [ -z "$server" ]; then
        return 1
    fi

    /bin/echo $server | /bin/cut -d'=' -f2 | /usr/bin/tr -d ' '
}

function is_setup_puppet_server() {
    get_puppet_server 1>/dev/null
    return $?
}

function change_puppet_server() {
    while true; do
        echo "Set Puppet server: " | colorize_question 1>&2
        read puppet_server
        if [ -z "$puppet_server" ]; then
            echo "Empty Puppet server!" | colorize_err
        else
            break
        fi
    done

    if is_setup_puppet_server; then
        /bin/sed -E -i "s/^[[:space:]]*server[[:space:]]?=[[:space:]]?.*$/    server = $puppet_server/g" $CONFIG_PUPPET
    else
        /bin/echo -e "\n    server = $puppet_server" >> $CONFIG_PUPPET
    fi

    return $?
}

if is_setup_puppet_server; then
    echo -n "Current Puppet server is "
    echo $(get_puppet_server) | colorize_highlight
    echo "Do you want to change Puppet server [y/n]?" | colorize_question 1>&2
else
    echo "Puppet server is not setup"
    echo "Do you want to setup Puppet server [y/n]?" | colorize_question 1>&2
fi
if prompt_yes; then
    change_puppet_server
fi
echo
    
#everything is ready
echo "Puppet agent is properly installed and setup" | colorize_highlight 
echo

#run puppet agent asu service
function activate_puppet_service() {
    /sbin/chkconfig puppet on
    /etc/init.d/puppet restart
}

echo "Do you want to activate Puppet agent service [y/n]?" | colorize_question 1>&2
if prompt_yes; then
    activate_puppet_service
fi
echo

#manually run puppat agent
function run_puppet_agent_now() {
    /usr/bin/puppet agent --test
}

echo "Do you want to run Puppet agent now [y/n]?" | colorize_question 1>&2
if prompt_yes; then
    run_puppet_agent_now
fi
echo
