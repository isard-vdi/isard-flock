IN_PATH=/opt/isard/images

for i in $(ls $IN_PATH/*.tar); do
	docker load -i $IN_PATH/$i
done
