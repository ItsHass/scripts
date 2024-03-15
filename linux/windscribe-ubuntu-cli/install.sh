sudo apt-get install apt-transport-https ca-certificates -y
echo 'deb https://repo.windscribe.com/ubuntu bionic main' | sudo tee /etc/apt/sources.list.d/windscribe-repo.list
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-key FDC247B7
sudo apt-get update
sudo apt-get install windscribe-cli
