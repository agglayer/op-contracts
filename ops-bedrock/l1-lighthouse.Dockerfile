FROM sigp/lighthouse:v8.1.3

COPY l1-lighthouse-bn-entrypoint.sh /entrypoint-bn.sh
COPY l1-lighthouse-vc-entrypoint.sh /entrypoint-vc.sh

VOLUME ["/db"]
