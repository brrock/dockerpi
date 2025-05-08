# How to Build the image your self
1. Run setup to get files ready 
```sh
chmod +x ./prep.sh
./prep.sh
```
2. Build Docker image 
```sh
# Tag can be anything
docker build -t dockerpi .
```