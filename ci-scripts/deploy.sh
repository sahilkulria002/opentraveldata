#!/bin/sh
#
# Location of this script:
# https://github.com/opentraveldata/opentraveldata/blob/master/ci-scripts/deploy.sh
#
# This script uploads a few OpenTravelData (OPTD) CSV data files
# onto transport-search.org web servers (aliased titsc and titscnew).
# There are two sets of CSV data files:
# 1. CSV data files maintained on this OPTD Git repository itself
#    (https://github.com/opentraveldata/opentraveldata)
#    The ci-scripts/titsc_delivery_map.csv CSV contains the list of CSV files
#    to be copied from the OPTD Git repo to titsc/titscnew
# 2. CSV data files generated by the Quality Assurance (QA) checkers
#    (https://github.com/opentraveldata/quality-assurance/tree/master/checkers)
#    All the CSV files resulting from the QA checkers are to be copied
#    onto titsc/titscnew
#
# The environment variables set by Travis are specified
# in https://travis-ci.com/opentraveldata/opentraveldata/settings.
# It includes the encryption keys (encrypted_dd7324fa5dde_{iv,key})
#

#
export OPTD_QA_DIR="/tmp/opentraveldata-qa"
export OPTD_MAP_FILE="ci-scripts/titsc_delivery_map.csv"

#
echo "DATA_DIR_BASE=${DATA_DIR_BASE}"

if [ "${DATA_DIR_BASE}" == "" ]
then
        export DATA_DIR_BASE="/var/www/data/optd"
fi

# To be altered with the new target directories
export TODAY_DATE="$(date +%Y-%m-%d)"
export DATA_QA_DIR="${DATA_DIR_BASE}/qa/${TODAY_DATE}"

#
echo "Injecting a few host keys into ~/.ssh/known_hosts"
cat >> ~/.ssh/known_hosts << _EOF
www2-int2.transport-search.org ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBDmslzunyRnmtrJSwaP1vGuS+vTFBoodZRY1Ri+VIXR8qBKa4MGNgX5WfwQIEOCsbme4gzJ4BZHFNY8WAwNl500=
www-int2.transport-search.org ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBKuH70tG6Ep2ibfqkZMnhPhXan9uIEXuQXUMdNG7N8ZSTv713tO1moU/nVl/drrN68Z4bLD+Nj49OIhj/9OM/W8=
_EOF
chmod 600 ~/.ssh/known_hosts

#
#echo "Content of ~/.ssh/config"
#cat ~/.ssh/config
#echo "--"

#
extractTimeStamp() {
	if [ ! -f ${git_file} ]
	then
		echo
		echo "Error! The ${git_file} file (set by the \$git_file variable) does not seem to exist"
		echo
		exit 1
	fi

    # Extract the date and time from the Git time-stamp for that file
    declare -a ts_array=($(git log -1 --pretty=""format:%ci"" ${git_file} | cut -d' ' -f1,2))
    ts_date="${ts_array[0]}"
    ts_time="${ts_array[1]}"
    #echo "Date: ${ts_date} - Timee: ${ts_time}"
        
    # Extract the year, month and day
    declare -a ts_date_array=($(echo "${ts_date}" | sed -e 's/-/ /g'))
    ts_year="${ts_date_array[0]}"
    ts_month="${ts_date_array[1]}"
    ts_day="${ts_date_array[2]}"
    #echo "Year: ${ts_year} - Month: ${ts_month} - Day: ${ts_day}"

    # Extract the hour, minutes and seconds
    declare -a ts_time_array=($(echo "${ts_time}" | sed -e 's/:/ /g'))
    ts_hours="${ts_time_array[0]}"
    ts_mins="${ts_time_array[1]}"
    ts_secs="${ts_time_array[2]}"
    #echo "Hours: ${ts_hours} - Hours: ${ts_mins} - Seconds: ${ts_secs}"
}

#
syncOPTDFileToTITsc() {
	# Extract the details of OPTD data files
	org_dir="$(echo ${optd_map_line} | cut -d'^' -f1)"
	csv_filename="$(echo ${optd_map_line} | cut -d'^' -f2)"
	tgt_dir="$(echo ${optd_map_line} | cut -d'^' -f3)"

	# Index
	idx=$((idx+1))
	
	#
	csv_file="${org_dir}/${csv_filename}"
	if [ ! -f "${csv_file}" ]
	then
		echo "\n#####"
		echo "In ci-scripts/titsc_delivery_map.csv:${idx}"
		echo "\$org_dir=${org_dir}"
		echo "\$csv_filename=${csv_filename}"
		echo "\$tgt_dir=${tgt_dir}"
		echo "The origin CSV data file '${csv_file}' is missing in this repo"
		echo "It is expected to upload it to ${TITSC_SVR} into " \
			 "'${DATA_DIR_BASE}/cicd/${tgt_dir}'"
		echo "If that file has been removed from the OPTD repository, " \
			 "please update ${OPTD_MAP_FILE}"
		echo "#####\n"
		exit 1
	fi

	#
	git_file="${csv_file}"
	extractTimeStamp

	# Reporting
	echo
	echo "---- [${TITSC_SVR}][${idx}] OPTD data file: ${csv_file} - " \
		 "Last update date-time: ${ts_date} ${ts_time} ----"
	echo

	# Specify the target remote directory.
	# Example with opentraveldata/optd_por_ref.csv:
	# /var/www/data/optd/cicd/por/2017/12/11/00:01:11
	tgt_rmt_dir="${DATA_DIR_BASE}/cicd/${tgt_dir}/${ts_year}/${ts_month}/${ts_day}/${ts_time}"

	# Create the remote target directories, if necessary
	echo "Creating ${tgt_rmt_dir} on to cicd@${TITSC_SVR}..."
	ssh -o StrictHostKeyChecking=no cicd@${TITSC_SVR} \
		"mkdir -p ${tgt_rmt_dir}"
	ssh -o StrictHostKeyChecking=no qa@${TITSC_SVR} \
		"mkdir -p ${DATA_QA_DIR}/to_be_checked"
	
	# Upload to [www|www2].transport-search.org server
	echo "Synchronizing ${csv_file} onto cicd@${TITSC_SVR} " \
		 "in ${tgt_rmt_dir}..."
	rsync -rav -e "ssh -o StrictHostKeyChecking=no" \
		  ${csv_file} cicd@${TITSC_SVR}:${tgt_rmt_dir}/
	echo "... done"
	
	# Compress the remote data files
	echo "Compressing ${tgt_rmt_dir}/${csv_filename} " \
		 "on to cicd@${TITSC_SVR}..."
	time ssh -o StrictHostKeyChecking=no cicd@${TITSC_SVR} \
		 "bzip2 ${tgt_rmt_dir}/${csv_filename}"
	echo "... done"
	
	# Create a symbolic link remotely
	echo "Creating a symbolic between ${tgt_rmt_dir}/${csv_filename}.bz2 " \
		 "and ${DATA_QA_DIR}/to_be_checked/${csv_filename}.bz2 " \
		 "on to qa@${TITSC_SVR}..."
	ssh -o StrictHostKeyChecking=no qa@${TITSC_SVR} \
		"ln -sf ${tgt_rmt_dir}/${csv_filename}.bz2 " \
		"${DATA_QA_DIR}/to_be_checked/${csv_filename}.bz2"
	echo "... done"
	
	# Reporting
	echo
	echo "---- [${TITSC_SVR}][${idx}] OPTD data file: ${csv_file} - Done ----"
	echo
}

#
syncOPTDToTITsc() {
    echo
    echo "==== Uploading OPTD data files onto ${TITSC_SVR} ===="
    echo
	echo "OPTD data files:"
	cat ${OPTD_MAP_FILE}
	echo
    idx=0
	# The -u3 allows to use another file descriptor than the standard (input) one
	# as that latter may be used by the syncOPTDFileToTITsc function
    while IFS="" read -r -u3 optd_map_line
	do
		syncOPTDFileToTITsc
	done 3< ${OPTD_MAP_FILE}

    echo
    echo "==== Done uploading OPTD data files onto ${TITSC_SVR} ===="
    echo
}

#
syncQAToTITsc() {
    #
    echo
	echo "==== Uploading QA results onto ${TITSC_SVR} ===="
    echo "Synchronization of the CSV data files onto ${TITSC_SVR}"
    echo

    #
    echo "Creating ${DATA_QA_DIR} on to qa@${TITSC_SVR}..."
    ssh -o StrictHostKeyChecking=no qa@${TITSC_SVR} "mkdir -p ${DATA_QA_DIR}"
    echo "... done"

    #
    echo "Synchronizing ${OPTD_QA_DIR}/results onto qa@${TITSC_SVR}..."
    time rsync -rav --del -e "ssh -o StrictHostKeyChecking=no" \
		 ${OPTD_QA_DIR}/results qa@${TITSC_SVR}:${DATA_QA_DIR}/
    echo "... done"

    #
    echo
    echo "==== Done uploading QA results onto ${TITSC_SVR} ===="
    echo
}

##
# Clone the Quality Assurance (QA) repository
echo
echo "Cloning https://github.com/opentraveldata/quality-assurance " \
	 "into ${OPTD_QA_DIR}..."
git clone https://github.com/opentraveldata/quality-assurance.git ${OPTD_QA_DIR}
echo "... done"
echo

##
# Launch the Quality Assurance (QA)
echo
echo "==== Run the QA checkers ===="
echo

pushd ${OPTD_QA_DIR}
pip install -r requirements.txt
make PY_EXEC=python checkers
popd

echo
echo "==== Done with the QA checkers ===="
echo

##
# Upload of OPTD data files onto titsc/titscnew

# https://transport-search.org/data/optd/{qa,cicd}
TITSC_SVR="titsc"
syncOPTDToTITsc

# https://www2.transport-search.org/data/optd/{qa,cicd}
TITSC_SVR="titscnew"
syncOPTDToTITsc


##
# Upload of QA results onto titsc/titscnew

# https://transport-search.org/data/optd/{qa,cicd}
TITSC_SVR="titsc"
syncQAToTITsc

# https://www2.transport-search.org/data/optd/{qa,cicd}
TITSC_SVR="titscnew"
syncQAToTITsc

##
# Reporting
echo
echo "The OPTD data files have been uploaded:"
echo "* https://transport-search.org/data/optd/cicd/"
echo "* https://www2.transport-search.org/data/optd/cicd/"
echo

echo
echo "The Quality Assurance (QA) results have been uploaded:"
echo "* https://transport-search.org/data/optd/qa/"
echo "* https://www2.transport-search.org/data/optd/qa/"
echo
