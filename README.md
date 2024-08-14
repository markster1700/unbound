Unbound DNS is an excellent DNS server to run at home and your own network. One of the important features of Unbound DNS is Response Policy Zones.
Using RPZ functionality Unbound DNS can pass or block configured DNS entries. For many uses this can be used to manage and block ads, trackers and any unwanted domains.
What is missing from Unbound implementation is the utility to configure and load lists containing bad domains.

Provided here zone-load.sh script can be used to manage domain lists and auto reload Unbound when a given list has changed or was updated.
The file is using existing Unbound configuration to read domain lists, download updated list and reload Unbound.

Best practice is to create a separate configuration file listing all domain lists, then include the file in unbound.conf.
Here is a simple example.

zone.conf 

rpz:  
    name: blockhost  
    zonefile: /Users/Files/scripts/unbound/rpz.blockhost.txt  
  
rpz:  
    name: urlhause  
    url: https://urlhaus.abuse.ch/downloads/rpz/     
    zonefile: /Users/Files/scripts/unbound/rpz.urlhause.txt     
    
rpz:  
   name: stevenblack  
   #url: https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts   
   zonefile: /Users/Files/scripts/unbound/rpz.stevenblack.txt  
  
rpz:  
   name: smart-tv  
   zonefile: /Users/Files/scripts/unbound/rpz.smart-tv.txt  
  
The zone.conf file must be included in unbound.conf with the folowing  
  include: "/etc/unbound/<directory>/zone.conf"  
  
With the following example domain lists "smart-tv" and "blockhost" are static lists. It means these are managed by administrator manually.
Here is an example of "blockhost" file.  

$TTL 6h  
@ SOA rpz.blockhost.local. admin.rpz.blockhost.local. (373545058 6h 1h 1w 2h)  
  NS  localhost.  
; RPZ manual block hosts  
cookielaw.org CNAME .  
eclipsetrumpets.us CNAME .  
niltibse.net CNAME .  
stawhoph.com CNAME .  
worldhomeoutlet.com CNAME .  
  
From the zone.conf file we can see another example of Unbound RPZ "urlhause". This rpz entry will be proceeses and file updated automatically by unbound itself.
Since Unbound supports standrd rpz this is automaticly refreshed and reloaded.

Not all domain lists are published in rpz format and therefor we need ways to import these lists properly into unbound. zone-load.sh utility do just that.
Look at the example of "stevenblack" domain list. This list is not in rpz format. The utility will convert the list to rps format and also check if the file has changed before downloading it again. 

It is recommended to invoke zone-load.sh form cron periodically but you can run it manually. To execute zone-load.sh from cron inclue the following in cron job but change the directory name where the file exists.
  
*/30 * * * * /etc/unbound/zones/zone-load.sh -c zone.conf  

