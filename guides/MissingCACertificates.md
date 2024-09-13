# How to add a CA Certificate so that SSL checks work correctly

When using the Template [Website certificate by Zabbix agent 2](https://git.zabbix.com/projects/ZBX/repos/zabbix/browse/templates/app/certificate_agent2?at=release/7.0) to check SSL Certificate validity for Websites, you may run into an issue where either to root CA or one of the Intermediate certificates is not trusted by the machine running Zabbix Agent 2 that is performing the check.

In the below example, the missing certificate was the `DigiCert Global G2 TLS RSA SHA256 2020 CA1` Intermediate certificate.

## Issue Symptoms

Errors that might appear Trigger notifications will be similar to Certificate is Invalid.

When checking via `zabbix_get`, you recieve an error similar to the following:

```bash
sudo zabbix_get -s 127.0.0.1 -k web.certificate.get['website.contoso.com']
{"x509":{"version":3,"serial_number":"00000000000000000000000000000000","signature_algorithm":"SHA512-RSA","issuer":"CN=DigiCert Global G2 TLS RSA SHA256 2020 CA1,O=DigiCert Inc,C=US","not_before":{"value":"Apr 17 00:00:00 2024 GMT","timestamp":1713312000},"not_after":{"value":"May 18 23:59:59 2025 GMT","timestamp":1747612799},"subject":"CN=website.contoso.com,O=Contoso,L=Some Place,ST=Some State,C=US","public_key_algorithm":"RSA","alternative_names":["website.contoso.com"]},"result":{"value":"invalid","message":"failed to verify certificate: x509: certificate signed by unknown authority"},"sha1_fingerprint":"0000000000000000000000000000000000000000","sha256_fingerprint":"0000000000000000000000000000000000000000000000000000000000000000"}
```

## Resolution

Install the certificate. Obviously. /sarc

However, if you are here, it's likely, that like me, you are having issues with getting the certificate to stick.

After several attempts to download the intermediate certificate in a .crt format, and update-ca-certificates I kept getting hit with an error:

```bash
user@nunyabusiness:/usr/share/ca-certificates$ sudo update-ca-certificates
Updating certificates in /etc/ssl/certs...
rehash: warning: skipping DigiCertGlobalG2TLSRSASHA2562020CA1-1.pem,it does not contain exactly one certificate or CRL
1 added, 0 removed; done.
Running hooks in /etc/ca-certificates/update.d...
done.
```

The part "it does not contain exactly one certificate or CRL" caused me no end of grief, as the .crt provided by the vendor was an encrypted file.

In the end, it was thanks to [Bai](https://askubuntu.com/users/41616/bai) on [AskUbuntu](https://askubuntu.com/a/94861) that the penny dropped, and I was able to resolve my issue.

```bash
# make a new directory for extra certificates
sudo mkdir /usr/local/share/ca-certificates/extra
# download the .pem file
wget https://cacerts.digicert.com/DigiCertGlobalG2TLSRSASHA2562020CA1-1.crt.pem -O DigiCertGlobalG2TLSRSASHA2562020CA1-1.crt.pem
# convert to a .crt
openssl x509 -in DigiCertGlobalG2TLSRSASHA2562020CA1-1.crt.pem -inform PEM -out DigiCertGlobalG2TLSRSASHA2562020CA1-1.crt
# copy the certificate to the correct folder
sudo sudo cp DigiCertGlobalG2TLSRSASHA2562020CA1-1.crt /usr/share/ca-certificates/extra/
# reconfigure the certificates
# when prompted, select the new cert
sudo dpkg-reconfigure ca-certificates
# restart the zabbix-agent2 service
sudo service zabbix-agent2 restart
# do the check
sudo zabbix_get -s 127.0.0.1 -k web.certificate.get['website.contoso.com']
{"x509":{"version":3,"serial_number":"00000000000000000000000000000000","signature_algorithm":"SHA512-RSA","issuer":"CN=DigiCert Global G2 TLS RSA SHA256 2020 CA1,O=DigiCert Inc,C=US","not_before":{"value":"Apr 17 00:00:00 2024 GMT","timestamp":1713312000},"not_after":{"value":"May 18 23:59:59 2025 GMT","timestamp":1747612799},"subject":"CN=website.contoso.com,O=Contoso,L=Some Place,ST=Some State,C=US","public_key_algorithm":"RSA","alternative_names":["website.contoso.com"]},"result":{"value":"valid","message":"certificate verified successfully"},"sha1_fingerprint":"0000000000000000000000000000000000000000","sha256_fingerprint":"0000000000000000000000000000000000000000000000000000000000000000"}
```

Note the certificate check is now valid.
