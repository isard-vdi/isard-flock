#!/usr/bin/python
# coding: utf-8
###################################################################
# License: GPLv3
# Author: IsardVDI
# Version: 0.1
# Description: Api that can receive commands from pacemaker fence_relay
# agent.
# Requirements: yum install python-flask libvirt-python
##################################################################
from flask import Flask, request, jsonify
import libvirt

app = Flask(__name__)

## Adapt to your simulation system
apikey ="0123456789ABCDEF"
kvm_host_ip="192.168.122.1"

@app.route('/api/relay/<rn>') #, methods = ["GET", "POST"])
def entry_point():
    try:
        if request.args.get('apikey') != apikey: return jsonify({}), 403
    except:
        return jsonify({}), 403

    try:
        value = request.args.get('value')
    except:
        value = None
            
    if value is not None:
        try:
            status=set_relay_status(rn,int(value))
            return jsonify({"status":int(value)}), 200
        except:
            return jsonify({}), 500     

    try:
        status=get_relay_status(rn)
        return jsonify({"status":status}), 200
    except:
        return jsonify({}), 500   
            
if __name__ == '__main__':
    app.run(host='0.0.0.0',port=80,debug=True)
