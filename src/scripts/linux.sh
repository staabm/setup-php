# Function to log start of a operation
step_log() {
  message=$1
  printf "\n\033[90;1m==> \033[0m\033[37;1m%s\033[0m\n" "$message"
}

# Function to log result of a operation
add_log() {
  mark=$1
  subject=$2
  message=$3
  if [ "$mark" = "$tick" ]; then
    printf "\033[32;1m%s \033[0m\033[34;1m%s \033[0m\033[90;1m%s\033[0m\n" "$mark" "$subject" "$message"
  else
    printf "\033[31;1m%s \033[0m\033[34;1m%s \033[0m\033[90;1m%s\033[0m\n" "$mark" "$subject" "$message"
  fi
}

# Function to update php ppa
update_ppa() {
  if [ "$ppa_updated" = "false" ]; then
    find /etc/apt/sources.list.d -type f -name 'ondrej-ubuntu-php*.list' -exec sudo DEBIAN_FRONTEND=noninteractive apt-fast update -o Dir::Etc::sourcelist="{}" ';' >/dev/null 2>&1
    ppa_updated="true"
  fi
}

# Function to setup extensions
add_extension() {
  extension=$1
  install_command=$2
  prefix=$3
  if ! php -m | grep -i -q -w "$extension" && [ -e "$ext_dir/$extension.so" ]; then
    echo "$prefix=$extension" >>"$ini_file" && add_log "$tick" "$extension" "Enabled"
  elif php -m | grep -i -q -w "$extension"; then
    add_log "$tick" "$extension" "Enabled"
  elif ! php -m | grep -i -q -w "$extension"; then
    (eval "$install_command" && add_log "$tick" "$extension" "Installed and enabled") ||
    (update_ppa && eval "$install_command" && add_log "$tick" "$extension" "Installed and enabled") ||
    add_log "$cross" "$extension" "Could not install $extension on PHP $semver"
  fi
}

# Function to remove extensions
remove_extension() {
  extension=$1
  if [ -e /etc/php/"$version"/mods-available/"$extension".ini ]; then
    sudo phpdismod -v "$version" "$extension"
  fi
  sudo sed -i "/$extension/d" "$ini_file"
  sudo rm -rf /etc/php/"$version"/cli/conf.d/*"$extension"* >/dev/null 2>&1
  sudo rm -rf "$ext_dir"/"$extension".so >/dev/null 2>&1
}

# Function to update extension
update_extension() {
  extension=$1
  latest_version=$2
  current_version=$(php -r "echo phpversion('$extension');")
  final_version=$(printf "%s\n%s" "$current_version" "$latest_version" | sort | tail -n 1)
  if [ "$final_version" != "$current_version"  ]; then
    version_exists=$(apt-cache policy -- *"$extension" | grep "$final_version")
    if [ -z "$version_exists" ]; then
      update_ppa
    fi
    $apt_install php"$version"-"$extension"
  fi
}

# Function to setup a remote tool
add_tool() {
  url=$1
  tool=$2
  if [ ! -e /usr/local/bin/"$tool" ]; then
    rm -rf /usr/local/bin/"${tool:?}"
  fi
  status_code=$(sudo curl -s -w "%{http_code}" -o /usr/local/bin/"$tool" -L "$url")
  if [ "$status_code" = "200" ]; then
    sudo chmod a+x /usr/local/bin/"$tool"
    add_log "$tick" "$tool" "Added"
  else
    add_log "$cross" "$tool" "Could not setup $tool"
  fi
  if [ "$tool" = "composer" ]; then
    composer -q global config process-timeout 0
  fi
  if [ "$tool" = "phive" ]; then
    add_extension curl >/dev/null 2>&1
    add_extension mbstring >/dev/null 2>&1
    add_extension xml >/dev/null 2>&1
  fi
}

add_composer_tool() {
  tool=$1
  release=$2
  prefix=$3
  (
  composer global require "$prefix$release" >/dev/null 2>&1 && \
  sudo ln -sf "$(composer -q global config home)"/vendor/bin/"$tool" /usr/local/bin/"$tool" && \
  add_log "$tick" "$tool" "Added"
  ) || add_log "$cross" "$tool" "Could not setup $tool"
}

# Function to setup phpize and php-config
add_devtools() {
  if ! [ -e "/usr/bin/phpize$version" ] || ! [ -e "/usr/bin/php-config$version" ]; then
    $apt_install php"$version"-dev php"$version"-xml >/dev/null 2>&1
  fi
  sudo update-alternatives --set php-config /usr/bin/php-config"$version" >/dev/null 2>&1
  sudo update-alternatives --set phpize /usr/bin/phpize"$version" >/dev/null 2>&1
}

# Function to setup the nightly build from master branch
setup_master() {
  tar_file=php_"$version"%2Bubuntu"$(lsb_release -r -s)".tar.xz
  install_dir=~/php/"$version"
  sudo mkdir -m 777 -p ~/php
  $apt_install libicu-dev >/dev/null 2>&1
  curl -o "$tar_file" -L https://bintray.com/shivammathur/php/download_file?file_path="$tar_file" >/dev/null 2>&1
  sudo tar xf "$tar_file" -C ~/php >/dev/null 2>&1
  rm -rf "$tar_file"
  sudo ln -sf -S "$version" "$install_dir"/bin/* /usr/bin/
  sudo ln -sf "$install_dir"/etc/php.ini /etc/php.ini
}

# Function to setup PECL
add_pecl() {
  update_ppa
  add_devtools
  wget https://github.com/pear/pearweb_phars/raw/master/install-pear-nozlib.phar >/dev/null 2>&1
  sudo php install-pear-nozlib.phar >/dev/null 2>&1
  sudo rm -rf install-pear-nozlib.phar >/dev/null 2>&1
  sudo pear config-set php_ini "$ini_file" >/dev/null 2>&1
  sudo pear config-set auto_discover 1 >/dev/null 2>&1
  sudo pear channel-update pear.php.net >/dev/null 2>&1
  add_log "$tick" "PECL" "Added"
}

# Function to switch versions of PHP binaries
switch_version() {
  for tool in pear pecl php phar phar.phar php-cgi php-config phpize phpdbg; do
    if [ -e "/usr/bin/$tool$version" ]; then
      sudo update-alternatives --set $tool /usr/bin/"$tool$version" >/dev/null 2>&1
    fi
  done
}

# Variables
tick="✓"
cross="✗"
ppa_updated="false"
version=$1
apt_install="sudo DEBIAN_FRONTEND=noninteractive apt-fast install -y"
existing_version=$(php-config --version | cut -c 1-3)
semver=$(php -v | head -n 1 | cut -f 2 -d ' ' | cut -f 1 -d '-')

# Setup PHP
step_log "Setup PHP"
sudo mkdir -p /var/run
sudo mkdir -p /run/php

if [ "$existing_version" != "$version" ]; then
  if [ ! -e "/usr/bin/php$version" ]; then
    update_ppa
    ppa_updated=1
    if [ "$version" = "7.4" ]; then
      $apt_install php"$version" php"$version"-curl php"$version"-mbstring php"$version"-xml php"$version"-phpdbg >/dev/null 2>&1
    elif [ "$version" = "8.0" ]; then
      setup_master
    else
      $apt_install php"$version" php"$version"-curl php"$version"-mbstring php"$version"-xml >/dev/null 2>&1
    fi
    status="installed"
  else
    status="switched"
  fi

  switch_version

  semver=$(php -v | head -n 1 | cut -f 2 -d ' ' | cut -f 1 -d '-')
  if [ "$version" = "8.0" ]; then
    semver=$(php -v | head -n 1 | cut -f 2 -d ' ')
  fi

  if [ "$status" != "switched" ]; then
    status="Installed PHP $semver"
  else
    status="Switched to PHP $semver"
  fi
else
  status="PHP $semver Found"
fi

ini_file=$(php --ini | grep "Loaded Configuration" | sed -e "s|.*:s*||" | sed "s/ //g")
ext_dir=$(php -i | grep "extension_dir => /usr" | sed -e "s|.*=> s*||")
sudo chmod 777 "$ini_file"
add_log "$tick" "PHP" "$status"
