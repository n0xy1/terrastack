[bastion:vars]
ansible_user = ubuntu
ansible_python_interpreter = /usr/bin/python3

[win_servers:vars]
ansible_user=quokka
ansible_password=P@ssw0rd
ansible_connection=psrp
ansible_psrp_protocol=http
ansible_psrp_proxy=socks5h://127.0.0.1:10080

[win_servers]
%{ for ip in slice(ips, length(ips) - 2, length(ips)) ~}
${ip}
%{ endfor ~}

[win_servers:children]
domain_controllers

[domain_controllers]
${ips[0]}

[bastion]
${bastion_ip}

[attacker]
${attacker_ip}
