#!bash
if [ $(dirname $0) != "." ]; then
   echo "the script must be executed from its on directory"
   exit 1
else
   echo "trams"
   rm *.h;
   for i in $(find ../../ | grep \.h$); do ln -v -s $i .; done
fi