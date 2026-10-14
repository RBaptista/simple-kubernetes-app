FROM python:alpine
WORKDIR /usr/src/app
COPY . .
RUN pip3 install -r requirements.txt
EXPOSE 80
CMD [ "python", "main.py"]
