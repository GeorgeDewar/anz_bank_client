FROM ruby:3.0

WORKDIR /app

COPY . .

RUN gem install bundler && bundle install

CMD ["irb"]
