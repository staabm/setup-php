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
    exists=$(curl -sL https://pecl.php.net/json.php?package="$extension" -w "%{http_code}" -o /dev/null)
    if [ "$exists" = "200" ] || [[ "$extension" == "phalcon"* ]]; then
      (
        eval "$install_command" && \
        add_log "$tick" "$extension" "Installed and enabled"
      ) || add_log "$cross" "$extension" "Could not install $extension on PHP $semver"
    else
      if ! php -m | grep -i -q -w "$extension"; then
        add_log "$cross" "$extension" "Could not find $extension for PHP $semver on PECL"
      fi
    fi
  fi
}

# Function to remove extensions
remove_extension() {
  extension=$1
  sudo sed -i '' "/$1/d" "$ini_file"
  sudo rm -rf "$ext_dir"/"$1".so >/dev/null 2>&1
}

# Function to setup a remote tool
add_tool() {
  url=$1
  tool=$2
  if [ "$tool" = "composer" ]; then
    brew install composer >/dev/null 2>&1
    composer -q global config process-timeout 0
    add_log "$tick" "$tool" "Added"
  else
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

add_pecl() {
  add_log "$tick" "PECL" "Added"
}

# Function to setup PHP and composer
setup_php_and_composer() {
  export HOMEBREW_NO_INSTALL_CLEANUP=TRUE
  brew tap shivammathur/homebrew-php >/dev/null 2>&1
  brew install shivammathur/php/php@"$version" >/dev/null 2>&1
  brew link --force --overwrite php@"$version" >/dev/null 2>&1
}

# Variables
tick="✓"
cross="✗"
version=$1

# Setup PHP and composer
step_log "Setup PHP"
setup_php_and_composer
ini_file=$(php -d "date.timezone=UTC" --ini | grep "Loaded Configuration" | sed -e "s|.*:s*||" | sed "s/ //g")
echo "date.timezone=UTC" >> "$ini_file"
ext_dir=$(php -i | grep "extension_dir => /usr" | sed -e "s|.*=> s*||")
sudo chmod 777 "$ini_file"
mkdir -p "$(pecl config-get ext_dir)"
semver=$(php -v | head -n 1 | cut -f 2 -d ' ')
add_log "$tick" "PHP" "Installed PHP $semver"
