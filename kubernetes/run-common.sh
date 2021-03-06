function ensure_intalled {
  set_process "checking dependencies"; echo
  should_exit=''
  for i in $@; do
    if command -v $i &>/dev/null; then
      echo_ok "$i found"
    else
      echo_fail "$i is needed to run this script, but not installed"
      should_exit=1
    fi
  done
  if [ $should_exit ]; then
    exit 1
  fi
}

function ensure_submodules {
  set_process "checking submodules"
  if [ -n "$(git submodule status | grep -e '^-')" ]; then
    echo_fail "submodules are not initialized correctly"
    echo_fail "try running 'git submodule update --init --recursive'"
    exit 1
  else
    echo_ok "all submodules are initialized"
  fi
}

function start_cluster {
  set_process "starting cluster"
  if minikube status >/dev/null; then
    echo_ok "cluster already running"
  else
    run minikube start --kubernetes-version=v1.11.0 --memory 4096 --disk-size 40g
    echo_ok "started cluster"
  fi
}

function start_kafka {
  config_folder="`dirname $0`/kubernetes-kafka"
  set_process "configuring kafka"; echo
  set_process "configuring storage for kafka"
  run kubectl apply -f $config_folder/configure/minikube-storageclass-broker.yml
  run kubectl apply -f $config_folder/configure/minikube-storageclass-zookeeper.yml
  echo_ok "configured storage"
  set_process "configuring namespaces for kafka"
  run kubectl apply -f $config_folder/00-namespace.yml
  run kubectl apply -f $config_folder/rbac-namespace-default/
  echo_ok "configured namespaces"
  set_process "configuring the rest of kafka"
  run kubectl apply -f $config_folder/zookeeper/
  run kubectl apply -f $config_folder/kafka/
  echo_ok "configured kafka"
}

function start_parity {
  config_folder="`dirname $0`/parity"
  set_process "configuring parity"; echo
  set_process "configuring storage for parity"
  run kubectl apply -f $config_folder/configure/minikube-storageclass.yml
  echo_ok "configured storage"
  set_process "configuring the rest of parity"
  run kubectl apply -f $config_folder/
  echo_ok "configured parity"
}

function start_kafka_additions {
  config_folder="`dirname $0`/kafka-additions"
  set_process "configuring addtional services for kafka"; echo
  run kubectl apply -f $config_folder/
  echo_ok "configured addtional services for kafka"
}

function build_harvester {
  set_process "building harvester components"; echo
  run eval `minikube docker-env`
  set_process "building kafka-producer-blockchain"
  (run cd ../harvester/kafka-producer/kafka-producer-blockchain; run sbt -no-colors docker)
  set_process "building kafka-stream-balance"
  (run cd ../harvester/kafka-stream-balance; run sbt -no-colors docker)
  set_process "building kafka-stream-lastSeen"
  (run cd ../harvester/kafka-stream-lastSeen; run sbt -no-colors docker)
  echo_ok "built kafka-producer-blockchain"
}

function start_harvester {
  config_folder="`dirname $0`/harvester"
  set_process "configuring harvester"; echo
  set_process "creating harvester"
  run kubectl apply -f $config_folder/
  echo_ok "configured harvester"
}

function run_telepresence {
  set_process "starting telepresence"; echo
  user_shell=$(ps -p $(ps -p $$ -oppid=) -ocommand=)

  set_process "creating telepresence namespace"
  echo '{"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": "telepresence"}}' | kubectl apply -f -
  echo_ok "created telepresence namespace"

  set_process "running telepresence (with the $user_shell shell)"
  echo -n -e "\e[2K"
  echo "Will now run your current shell inside telepresence."
  echo "You may be prompted for sudo access, as it needs it to set things up."
  echo "You can stop it at any time by ^D (Ctrl-D) or by typing 'exit'"
  echo_ok "running telepresence"
  run_noredirect telepresence --namespace telepresence --also-proxy=172.17.0.0/16 --run $user_shell || :
  echo_ok "telepresence session finished"
}

function run {
  echo "[ RUN] $@" >> $logfile
  if [ $verbose != no ]; then
    echo "  \$ $@"
    "$@" > >(tee -a $logfile | indent) 2>&1
  else
    "$@" >> $logfile 2>&1
  fi
}

function run_noredirect {
  echo "[ RUN] $@" >> $logfile
  "$@"
}

current_process='working'
function print_process {
  echo -ne "$(tput el || true)$(echo $current_process | capitalize)...$(tput sgr0 || true)\r"
  # echo -ne "\e[2K[\e[0;30m....\e[0m] $(echo $current_process | capitalize)\n"
}

function set_process {
  current_process="$@"
  echo "[....] $(echo $current_process | capitalize)..." >> $logfile
  print_process
}

function handle_exit {
  echo_fail "An error occured while $current_process"
  echo "Here is a snip of the last 10 lines of $(tput setaf 3 || true)$logfile$(tput sgr0 || true):"
  head -n-1 $logfile | tail -n10 | indent
}

function echo_ok {
  echo "[ OK ] $(echo $@ | capitalize)!" >> $logfile
  echo -e "\r[$(tput el || true)$(tput setaf 2 || true) OK $(tput sgr0 || true)] $(echo $@ | capitalize)!"
  print_process
}

function echo_fail {
  echo "[FAIL] $(echo $@ | capitalize)!" >> $logfile
  echo -e "\r[$(tput el || true)$(tput setaf 1 || true)FAIL$(tput sgr0 || true)] $(echo $@ | capitalize)!"
  print_process
}

function indent {
  sed 's/^/  /'
}

function capitalize {
  read -n1 first_letter
  echo -n $first_letter | tr '[:lower:]' '[:upper:]'
  cat
}
