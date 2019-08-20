#!/usr/bin/python
# coding: utf-8
## yum install python-flask libvirt-python
from flask import Flask, request, jsonify
import libvirt

app = Flask(__name__)

## Adapt to your simulation system
apikey ="0123456789ABCDEF"
kvm_host_ip="192.168.122.1"

@app.route('/api/relay/0') #, methods = ["GET", "POST"])
def entry_point():
    host=int(request.host[-1])
    try:
        if request.args.get('apikey') != apikey: return jsonify({}), 403
    except:
        return jsonify({}), 403

    # ~ if host == 0: 
    try:
        value = request.args.get('value')
    except:
        value = None
            
    if value is not None:
        if value == "1": 
            conn = libvirt.open("qemu+ssh://root@"+kvm_host_ip+"/system")
            dom = conn.lookupByName("if"+str(host))
            if not dom.isActive(): dom.create()
            conn.close()
            return jsonify({"relay/0":1}), 200
        if value == "0": 
            conn = libvirt.open("qemu+ssh://root@"+kvm_host_ip+"/system")
            dom = conn.lookupByName("if"+str(host))
            if dom.isActive(): dom.destroy()
            conn.close()
            return jsonify({"relay/0":0}), 200
        return jsonify({}), 500
    
    # ~ status=virsh list | grep VM[host-1]
    conn = libvirt.open("qemu+ssh://root@"+kvm_host_ip+"/system")
    try:
        dom = conn.lookupByName("if"+str(host))
        if dom.isActive(): 
            conn.close()
            return jsonify({"relay/0":1}), 200
        else:
            conn.close()
            return jsonify({"relay/0":0}), 200
    except:
        conn.close()
        return jsonify({"relay/0":0}), 200        

if __name__ == '__main__':
    app.run(host='0.0.0.0',port=80,debug=True)
