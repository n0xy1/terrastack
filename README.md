# Terra Stack

Provisions an Active Directory environment on Openstack with Terraform.
Once provisioned, ansible configures the environment. 

(some hard coded creds are in here.. probably needs sanitisation.)

Export the following to make ansible work through the bastion (when on a mac):
```
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
```

Specify the location of the SOPS key.
```
export SOPS_AGE_KEY_FILE=/Users/d/.config/age/terraform_key.txt
```


