#!/bin/ksh

# Get the list of hosts dynamically using RemRun!
hosts=$(RemRun! -S "if [ -e /usr/lib/printerc ] ; then hostname; fi")

# Check if the 'hosts' variable is empty (i.e., no hosts returned)
if [ -z "$hosts" ]; then
    echo "No hosts found with /usr/lib/printerc file."
    exit 1
fi

# Loop through each host
for host in $hosts; do
    echo "Running commands on $host..."

    # Run piomkjetd commands remotely using ssh
ssh $host "/usr/lib/lpd/pio/etc/piomkjetd mkpq_jetdirect -p 'scc_label' -D asc -q 'queue_name' -h 'dns_name' -x '9100'"

    # Append printer configuration to /usr/lib/printerc remotely

ssh $host "echo 'Printerc_name     !LZ1:5360:lp -c -dqueue_name >/dev/null 2>&1' >>/usr/lib/printerc"
    echo "Completed setup on $host."
done

echo "Printer setup completed on all hosts."  
