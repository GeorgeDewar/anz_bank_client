# ANZ Bank Client

This gem is a client for the private, undocumented API behind ANZ New Zealand's personal internet banking website. It is
not affiliated with ANZ Bank in any way and is intended only for personal use.

It can be used in a Ruby script or application, or alternatively as a command-line tool (anzcli).

It is currently capable of logging in and retrieving account balances and transaction history, but could be easily
extended to do other things. Please note that this gem is not officially supported by ANZ Bank and may stop working at
any time due to changes to how their internet banking application works. ANZ's terms and conditions for their internet
banking product may also change at any time, and you should ensure that you are complying with them if you use this gem.

## Use as a command line tool

Install the gem globally with `gem install anz_bank_client` and then run `anzcli` to get started.

You can use the `help` option to see a list of available commands and options.

```
anzcli commands:
  anzcli help [COMMAND]                  # Describe available commands or one specific command
  anzcli login                           # Login to ANZ
  anzcli logout                          # Logout
  anzcli ls-accounts                     # List accounts
  anzcli ls-transactions ACCOUNT_NUMBER  # List transactions

Options:
  -f, [--format=FORMAT]  # Output format
                         # Default: table
                         # Possible values: table, json
```

The remaining sections are about using the gem in a Ruby script or application.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'anz_bank_client'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install anz_bank_client

## Usage

First, create an instance of the client.

```ruby
@session = AnzBankClient::Session.new
```

Then, log in.

```ruby
@session.login(customer_number, password)
```

You can then list accounts and transactions.

```ruby
accounts = @session.list_accounts

first_account_number = accounts.first[:accountNo] # e.g. 01-1234-5678901-00
start_date = Date.today.prev_month.to_s
end_date = Date.today.to_s
transactions = @session.list_transactions(first_account_number, start_date, end_date)
```

Finally, log out.

```ruby
@session.logout
```

It's very important to log out, as ANZ's internet banking application has a maximum number of concurrent sessions and
you could lock yourself out of your account for a while if you create too many of them without logging out.

## Running with Docker Compose

You can use Docker Compose to run this gem in a containerized environment.

1. **Start the service:**

   ```sh
   docker compose up -d
   ```

2. **Access the running container:**

   ```sh
   docker ps

   # Find the container name or ID for the ANZ Bank Client service, then run:

   docker exec -it <container_name_or_id> /bin/bash
   ```

   From inside the container, you can run CLI commands such as:

   ```sh
   /app/exe/anzcli login
   /app/exe/anzcli ls-accounts
   ```

3. **Configure environment variables:**

   Set your credentials using environment variables, either in a `.env` file or directly in your Compose configuration:

   - `ANZ_CUSTOMER_NO` – Your ANZ customer number
   - `ANZ_PASSWORD` – Your ANZ password

   Example `.env` file:

   ```env
   ANZ_CUSTOMER_NO=your_customer_number
   ANZ_PASSWORD=your_password
   ```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/GeorgeDewar/anz_bank_client.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
