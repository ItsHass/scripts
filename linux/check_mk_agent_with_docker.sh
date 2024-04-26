wget http://192.168.0.31:8080/cmk/check_mk/agents/check-mk-agent_2.4.0-2024.04.26-1_all.deb
sudo apt install ./check-mk-agent_2.4.0-2024.04.26-1_all.deb -y

sudo apt install python3-pip -y

wget http://192.168.0.31:8080/cmk/check_mk/agents/plugins/mk_docker.py

pip3 install docker

pip3 --version
