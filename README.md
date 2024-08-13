Unbound DNS is an excellent DNS server to run at home and your own network. One of the important features of Unbound DNS is Response Policy Zones.
Using RPZ functionality Unbound DNS can pass or block configured DNS entries. For many uses this can be used to manage and block ads, trackers and any unwanted domains.
What ius missing from Unbound implementaion is utility to configure and load lists contaioning bad domains.

Provided here zone-load.sh script can be used to manage domain lists and auto reload Unbound when necessary. 
