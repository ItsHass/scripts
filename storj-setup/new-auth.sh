clear

read -p "Enter Storj Node Name: " NodeName

echo Please Authorise.
read -p "Auth Key: " AuthKey
identity authorize $NodeName $AuthKey

grep -c BEGIN ~/.local/share/storj/identity/$NodeName/ca.cert
grep -c BEGIN ~/.local/share/storj/identity/$NodeName/identity.cert

echo "2 and 3 shoudl be shown above to confirm identity is authorised."
echo Storj Identity Setup Complete.
