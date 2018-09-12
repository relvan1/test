#!/bin/bash

working_dir=`pwd`

rm -rf cluster.csv
rm -rf mapper.csv

echo "Welcome to LoadTest Setup"
echo "-------------------------"

userOption=true

while $userOption; do

read -p "Do you want to run Single-Region Test (or) Multi-Region Test [S/M]: " testStatus

        if [[ $testStatus == 'S' || $testStatus == 's' ]]; then
		#read -p "Please Name your cluster: " clusterName

		### User Selecting Region and Zones ###
		echo "Available Regions in US"
		echo "-----------------------"
		echo "us-central1 | us-east1 | us-east4 | us-west1 | us-west2"
		echo ""
  		read -p "Select the Region: " regionSelect
		echo ""
  		case $regionSelect in
   				us-central1)
                			echo "Available Zones in $regionSelect"
					echo "--------------------------------"
                			echo "us-central1-a | us-central1-b | us-central1-c | us-central1-f"
					echo ""
                			read -p "Select anyone Zone for the cluster: " zoneSelect
                			;;
       				us-east1)
               				echo "Available Zones in $regionSelect"
			                echo "--------------------------------"
					echo "us-east1-b | us-east1-c | us-east1-d"
					echo ""
			                read -p "Select anyone Zone for the cluster: " zoneSelect
			                ;;
			        us-east4)
			                echo "Available Zones in $regionSelect"
					echo "--------------------------------"
			                echo "us-east4-a | us-east4-b | us-east4-c"
					echo ""
			                read -p "Select anyone Zone for the cluster: " zoneSelect
			                ;;
			        us-west1)
			                echo "Available Zones in $regionSelect"
					echo "--------------------------------"
			                echo "us-west1-a | us-west1-b | us-west1-c"
					echo ""
			                read -p "Select anyone Zone for the cluster: " zoneSelect
			                ;;
				us-west2)	
			                echo "Available Zones in $regionSelect"
					echo "--------------------------------"
			                echo "us-west2-a | us-west2-b | us-west2-c"
					echo ""
			                read -p "Select anyone Zone for the cluster: " zoneSelect
			                ;;
			        *)
			                echo "You Entered Wrong Input. Please Try Again.."
			                ;;
				esac
		clusterName=${regionSelect}-cluster
		echo "$clusterName,$zoneSelect">cluster.csv
                echo ""
		sleep 2
		echo "Our Default Cluster configuration"
		echo "---------------------------------------------"
		sleep 1 
	        echo "DB-Node (1-Grafana pod, 1-Influx pod)"
		sleep 1
	        echo "Master-Node (1-Master pod)"
	    	sleep 1
	        echo "Slave-Node (1-Slave pods)"
		sleep 1
		echo ""
		echo ""
		sleep 3
		echo "If you need different setup... please contact cluster admin"
		echo ""
		echo ""
		sleep 2

		###Creating Cluster in GKE with Default Values###
		echo "Cluster is getting ready......Please wait sometime"
		echo ""
		gcloud container clusters create $clusterName --zone $zoneSelect --num-nodes=1
		echo ""
		echo ""
		echo "GKE Cluster Created... Working on NodePools"
#		echo ""
#               echo ""
#		gcloud container node-pools delete default-pool --cluster $clusterName --zone $zoneSelect --quiet 
#		echo "Deleted the Default NodePools"
		echo ""
                echo ""
		gcloud container node-pools create grafana-influx --cluster $clusterName --zone $zoneSelect --machine-type=n1-standard-4 --image-type=ubuntu --node-labels=type=storage-and-monitoring --num-nodes=1 
		echo "Created Grafana-Influx NodePool"
		echo ""
                echo ""
		gcloud container node-pools create master --cluster $clusterName --zone $zoneSelect --machine-type=n1-standard-2 --image-type=ubuntu --node-labels=type=master --num-nodes=1
		echo "Created Master NodePool"
		echo ""
                echo ""
		gcloud container node-pools create slave --cluster $clusterName --zone $zoneSelect --machine-type=n1-standard-16 --image-type=ubuntu --node-labels=type=slave --num-nodes=1
		echo "Created Slave NodePool"
		echo ""
		sleep 2
		echo "Complete Cluster is Ready Now..Start deploying Pods"

		echo ""
                echo ""
                gcloud container node-pools delete default-pool --cluster $clusterName --zone $zoneSelect --quiet > /dev/null 2>&1  &
                echo "Deleting the Default NodePools"
                echo ""
                echo ""


		###Connecting with the Newly Created Cluster###
                echo ""
		echo "Connecting to the Cluster"
		gcloud container clusters get-credentials $clusterName --zone $zoneSelect --project etsyperftesting-208619
                echo "Connected to the cluster"
		tenant=$clusterName
		
		echo ""

		echo "Deploying Pods and Services for Loadtest...."
		echo "------------------------------------"

		kubectl create namespace $tenant

		###Creating Slave from YAML files###
		echo ""
		echo ""
		kubectl create -n $tenant -f $working_dir/jmeter_slaves_deploy.yaml

		kubectl create -n $tenant -f $working_dir/jmeter_slaves_svc.yaml
		echo "Slaves Part Created"

		###Creating Master from YAML files###
		echo ""
		echo ""
		kubectl create -n $tenant -f $working_dir/jmeter_master_configmap.yaml

		kubectl create -n $tenant -f $working_dir/jmeter_master_deploy.yaml
		echo "Master Part Created"

		###Creating InfluxDB from YAML files###
		echo ""
		echo ""
		kubectl create -n $tenant -f $working_dir/jmeter_influxdb_configmap.yaml

		kubectl create -n $tenant -f $working_dir/jmeter_influxdb_deploy.yaml

		kubectl create -n $tenant -f $working_dir/jmeter_influxdb_svc.yaml
		echo "Influx Part Created"

		###Creating Grafana from YAML files###
		echo ""
		echo ""
		kubectl create -n $tenant -f $working_dir/jmeter_grafana_deploy.yaml

		kubectl create -n $tenant -f $working_dir/jmeter_grafana_svc.yaml
		echo "Grafana Part Created"

		echo namespace = $tenant > $working_dir/tenant_export
                
		sleep 30

		###Creating Jmeter DB in Influx###
		echo "Creating the Jmeter DB"
		influxdb_pod=`kubectl get po -n $tenant | grep influxdb-jmeter | awk '{print $1}'`
		kubectl exec -ti -n $tenant $influxdb_pod -- influx -execute 'CREATE DATABASE jmeter'

		## Create the influxdb datasource in Grafana
		echo "Creating the Influxdb data source"
		grafana_pod=`kubectl get po -n $tenant | grep jmeter-grafana | awk '{print $1}'`

		kubectl exec -ti -n $tenant $grafana_pod -- curl 'http://admin:admin@127.0.0.1:3000/api/datasources' -X POST -H 'Content-Type: application/json;charset=UTF-8' --data-binary '{"name":"jmeterdb","type":"influxdb","url":"http://jmeter-influxdb:8086","access":"proxy","isDefault":true,"database":"jmeter","user":"admin","password":"admin"}' 

		###Applying MountPaths in Master Pod###
		master_pod=`kubectl get po -n $tenant | grep jmeter-master | awk '{print $1}'`
		kubectl exec -ti -n $tenant $master_pod -- cp  /load_test  /jmeter/load_test

		kubectl exec -ti -n $tenant $master_pod -- chmod 755 /jmeter/load_test
		
		echo ""
		echo "Settings Applied for LoadTest"
		echo ""
		sleep 20
                

		
		### Getting JMX and CSV Files###
		echo "Upload LoadTest scripts..."
		echo "--------------------------"
                echo ""
		validateFile () {
		        if [ -f $1 ];then
                		return 0
		        else
                	echo "file not exists";
		                exit 1
		        fi
		}

		read -p "Enter jmx file : " jmxFile
		validateFile $jmxFile
		echo "Started to copy the JMX files..."
                master_pod=`kubectl get po -n $tenant | grep jmeter-master | awk '{print $1}'`
                kubectl exec -it -n $tenant $master_pod -- bash -c "echo 35.227.203.198 www.etsy.com etsy.com openapi.etsy.com api.etsy.com >> /etc/hosts"
                kubectl cp $jmxFile -n $tenant $master_pod:/$jmxFile
		echo "JMX Copy process completed"
		echo ""
		echo ""
		csvOption=true;
		while $csvOption;
		do
		read -p "You want to pass csv file [y/n] " csvStatus
                if [ $csvStatus ];then  
			if [[ $csvStatus == 'y' || $csvStatus == 'Y' ]];then
				echo ""
        			read -p "Does this JMX need Single or Multiple CSV files [S/M]: " csvFile
          				 if [[ $csvFile == 'S' || $csvFile == 's' ]]; then
                 				read -p "Enter csv file : " csv
                 				validateFile $csv
						slave_pod=`kubectl get po -n $tenant | grep jmeter-slave | awk '{print $1}'`
						echo "Please wait for few moments.. we are copying the CSV file"
                				for i in $slave_pod
                				do
                				kubectl exec -ti -n $tenant $i -- mkdir -p /jmeter/apache-jmeter-4.0/bin/csv/
                				kubectl cp $csv -n $tenant $i:/jmeter/apache-jmeter-4.0/bin/csv/$csv
                				kubectl exec -it -n $tenant $i -- bash -c "echo 35.227.203.198 www.etsy.com etsy.com openapi.etsy.com api.etsy.com >> /etc/hosts"
                				done
						echo "CSV Copy Process completed"
						csvOption=false;
          				 elif [[ $csvFile == 'M' || $csvFile == 'm' ]]; then
						 csvMORE=true
						 while $csvMORE;
					         do
						 read -p "Enter csv file : " csv
                                                 validateFile $csv
						 echo "Please wait for few moments.. we are copying the CSV file"
                                                 slave_pod=`kubectl get po -n $tenant | grep jmeter-slave | awk '{print $1}'`
                                                 for i in $slave_pod
                                                 do
                                                 kubectl exec -ti -n $tenant $i -- mkdir -p /jmeter/apache-jmeter-4.0/bin/csv/
                                                 kubectl cp $csv -n $tenant $i:/jmeter/apache-jmeter-4.0/bin/csv/$csv
                                                 kubectl exec -it -n $tenant $i -- bash -c "echo 35.227.203.198 www.etsy.com etsy.com openapi.etsy.com api.etsy.com >> /etc/hosts"
                                                 done
						 echo "CSV Copy Process completed"
						 read -p "Do you have another CSV [Y/n]: " multiCSV
						     if [[ $multiCSV == 'y' || $multiCSV == 'Y' ]]; then
						        	csvMORE=true;
						     elif [[ $multiCSV == 'n' || $multiCSV == 'N' ]]; then
                                                     		csvMORE=false;
						     else
							echo "Enter a valid response Y or N: "
								csvMORE=true
						     fi
						 csvOption=false;
					         done
         				 else
           				        echo  "Enter a valid response S or M ";
	          				csvOption=true;

          				 fi
			elif [[ $csvStatus == 'n'|| $csvStatus == 'N' ]];then
				csvOption=false;
			else
   			echo  "Enter a valid response y or n ";
   				csvOption=true;
			fi
		fi
		done 
		
		link=`kubectl get svc -n $tenant | grep jmeter-grafana | awk '{print $4}'`
		echo ""
		echo "Please load the IP in the browser for the Grafana Dashboard - http://$link/" 
		echo ""
		###Test Ready###
		read -p "Your Test is ready.. Press Y to start and N to exit [Y/n]: " startStatus
			start=true
			while $start; 
			do
        		if [[ $startStatus == 'y' || $startStatus == 'Y' ]]; then
				echo "Starting the Test"
                		kubectl exec -it -n $tenant $master_pod -- /jmeter/load_test $jmxFile &
                                sleep 20
                                read -p "Do you want to stop the test [Y/n]: " abort
                                        if [[ $abort == 'y' || $abort == 'Y' ]]; then
                                            kubectl -n $tenant exec -ti $master_pod -- bash /jmeter/apache-jmeter-4.0/bin/stoptest.sh
                                        elif [[ $abort == 'n' || $abort == 'N' ]]; then
						$start=false;
					else
                          		    echo  "Wrong Response"
                               		fi
                                exit 0;
       			elif [[ $startStatus == 'n' || $startStatus == 'N' ]]; then
	                	exit 0;
        		else
				echo  "Enter a valid response y or n: "
				$start=true;
			fi
			done
			userOption=false;
                elif [[ $testStatus == 'M' || $testStatus == 'm' ]]; then
                 	 echo "Multi-Region Test"
			 exit 0;
        	else
	   		echo  "Enter a valid response S or M:  "
  		 	userOption=true;
		fi
done
###Deleting the Cluster###
sleep 5
delete=true
while $delete; do
read -p "Do you want to delete the cluster [y/n]: " deleteCluster
      if [[ $deleteCluster == 'y' || $deleteCluster == 'Y' ]]; then
                 gcloud container clusters delete $clusterName --zone $zoneSelect --quiet
                 delete=true;
      elif [[ $deleteCluster == 'n' || $deleteCluster == 'N' ]]; then
                 delete=false;
      else
                 echo  "Enter a valid response y or n ";
                 delete=true;
      fi
 done

