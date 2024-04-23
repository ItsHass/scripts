sudo apt install unzip

clear

read -p "Enter Storj Node Name: " NodeName

curl -L https://github.com/storj/storj/releases/latest/download/identity_linux_amd64.zip -o identity_linux_amd64.zip
unzip -o identity_linux_amd64.zip
chmod +x identity
sudo mv identity /usr/local/bin/identity

identity create $NodeName
echo Identity Created.

echo Please Authorise.
read -p "Auth Key: " AuthKey
identity authorize $NodeName $AuthKey

grep -c BEGIN ~/.local/share/storj/identity/$NodeName/ca.cert
grep -c BEGIN ~/.local/share/storj/identity/$NodeName/identity.cert

echo "2 and 3 shoudl be shown above to confirm identity is authorised."
echo Storj Identity Setup Complete.
