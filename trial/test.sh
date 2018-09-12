#!/bin/bash

validateFile () {
                        if [ -f $1 ];then
                                return 0
                        else
                        echo "file not exists";
                                exit 1
                        fi
                }

                
                echo " NOTE: Enter the file in the current directory or if the file is in other directory, then please enter the file with absolute path"

                read -p "Enter jmx file : " jmxFile
                validateFile $jmxFile

                csvOption=true;
		while $csvOption;
		do
                read -p "You want to pass csv file [y/n] " csvStatus
                if [ $csvStatus ];then
                        if [[ $csvStatus == 'y' || $csvStatus == 'Y' ]];then
                                read -p "Does this JMX need Single or Multiple CSV files [S/M]: " csvFile
                                         if [ $csvFile == 'S' ]; then
                                                read -p "Enter csv file : " csv
                                                validateFile $csv
						csvOption=false;
                                         elif [ $csvFile == 'M' ]; then
                                                 echo "you selected multi file"
                                                 exit 0;
					else
                                        echo  "Enter a valid response S or M ";
                                                 csvOption=true;
                                        fi
				elif [ $csvStatus == 'n' ];then
					csvOption=false;
			else
                        echo  "Enter a valid response y or n ";
                                csvOption=true;
                        fi
		fi

                echo $jmxFile,$csv >>mapper.csv
		done

	bind -x '"\e":"cat mapper.csv\n"'
