# frozen_string_literal: true

begin
  require "dotenv/load"
rescue LoadError
  # Dotenv is not available, so move on without loading it. It's only used for development.
end
require_relative "anz_bank_client/version"
require "faraday"
require "faraday-cookie_jar"
require "faraday/follow_redirects"
require "base64"

module AnzBankClient
  class Error < StandardError; end

  def self.login(username, password)
    session = Session.new
    session.login(username, password)
    session
  end

  class Session
    def initialize
      @logger = Logger.new $stderr
      @logger.level = Logger::INFO

      @cookie_jar = HTTP::CookieJar.new
      @user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36"

      # Set IBCookieDetect cookie so it knows we have cookies enabled
      @cookie_jar.add(HTTP::Cookie.new(name: "IBCookieDetect", value: "1", domain: "digital.anz.co.nz", path: "/"))
      @client = Faraday.new(
        headers: { "User-Agent" => @user_agent },
        # proxy: "http://Thinkbook.local:8080",
        # :ssl => {:verify => false}
      ) do |builder|
        builder.response :follow_redirects
        builder.use Faraday::CookieJar, jar: @cookie_jar
        # builder.response :logger
        builder.adapter Faraday.default_adapter
      end
    end

    # Write the cookie jar out to a string so that the session can be restored later
    def export
      cookies = StringIO.new
      @cookie_jar.save(cookies, format: :yaml, session: true)
      {
        cookies: cookies.string,
        initialise_response: @initialise_response,
      }.to_json
    end

    # Load the cookie jar from a string to restore a session
    def load(str)
      json = JSON.parse(str)
      @initialise_response = json["initialise_response"]
      cookies = StringIO.new
      cookies.write(json["cookies"])
      cookies.rewind
      @cookie_jar.load(cookies, format: :yaml)
    end

    def login(username, password)
      @logger.info "Fetching login page"

      login_page = @client.get("https://digital.anz.co.nz/preauth/web/service/login")
      if login_page.status != 200
        raise "Error getting login page: #{login_page.status} #{login_page.body}"
      end

      @encryption_key = login_page.body.match(/encryptionKey: "(.*)",/)[1]
      @encryption_key_id = login_page.body.match(/encryptionKeyId: "(.*)",/)[1]

      # Encrypt password using encryption key
      encrypted_password = encrypt_password(password).strip

      # Log in
      @logger.info "Logging in as #{username}"
      response = @client.post("https://digital.anz.co.nz/preauth/web/service/login") do |req|
        req.headers = {
          "User-Agent" => @user_agent,
          "Accept" => "application/json",
          "Content-Type" => "application/json",
        }
        req.body = {
          userId: username,
          password: encrypted_password,
          "referrer": "",
          "firstPage": "",
          "publicKeyId": @encryption_key_id,
        }.to_json
      end
      if JSON.parse(response.body)["code"] != "success"
        raise "Error logging in: #{response.status}\n\n#{response.body}"
      end

      @logger.info "Fetching session details"
      response = @client.get("https://secure.anz.co.nz/IBCS/service/session?referrer=https%3A%2F%2Fsecure.anz.co.nz%2F")
      if response.status != 200
        raise "Session setup failed with status #{response.status}\n\n#{response.body}"
      end

      csrf_token_match = response.body.match(/sessionCsrfToken *= *"(.*)";/)
      unless csrf_token_match
        raise "Could not find CSRF token in page body:\n\n#{response.body}"
      end

      csrf_token = csrf_token_match[1]
      @logger.info "CSRF Token: #{csrf_token}"

      @logger.info "Getting initial details"
      response = @client.get("https://secure.anz.co.nz/IBCS/service/home/initialise")
      raise "Error getting initial details: #{response.status}\n\n#{response.body}" unless response.status == 200

      @initialise_response = JSON.parse(response.body)
    end

    def list_accounts
      @initialise_response["viewableAccounts"].map do |account|
        balance = account.dig("accountBalance", "amount")
        overdrawn = balance && (
          account.dig("accountBalance", "indicator") == "overdrawn" || account["isLoan"] || account["isCreditCard"]
        )
        normalised_balance = if balance
                               overdrawn ? -balance : balance
                             end

        {
          accountNo: account["accountNo"],
          nickname: account["nicknameEscaped"],
          accountType: account["productDescription"],
          customerName: account["accountOwnerName"],
          accountBalance: normalised_balance,
          availableFunds: account.dig("availableFunds", "amount"),
          isLiabilityType: account["isLoan"] || account["isCreditCard"],
          supportsTransactions: true,
          dynamicBalance: account["isInvestment"],
        }
      end
    end

    # Fetches transactions for an account
    #
    # @param account_no the account number (e.g. 01-1234-1234567-00)
    # @param start_date in iso8601 format
    # @param end_date in iso8601 format
    def list_transactions(account_no, start_date, end_date)
      @logger.info "Getting transactions for account #{account_no} from #{start_date} to #{end_date}"
      account_obj = @initialise_response["viewableAccounts"]
                     .find { |account| account["accountNo"] == account_no }
      if account_obj.nil?
        raise "Could not find account #{account_no}"
      end
      account_uuid = account_obj["accountUuid"]
      raise "Could not find account #{account_no}" unless account_uuid

      response = @client.get("https://secure.anz.co.nz/IBCS/service/api/transactions?account=#{account_uuid}&ascending=false&from=#{start_date}&order=postdate&to=#{end_date}")
      raise "Error getting transactions: #{response.status}\n\n#{response.body}" unless response.status == 200

      response_json = JSON.parse(response.body)
      transactions = response_json["transactions"]
      # Ignore transactions without an amount - these can be informational messages like "Finance Charge Rate Changed Today"
      transactions = transactions.filter{ |transaction| transaction["amount"] }
      transactions.map do |transaction|
        {
          date: transaction["date"],
          postedDate: transaction["postedDate"],
          details: transaction["details"],
          amount: transaction["amount"]["amount"],
          currencyCode: transaction["amount"]["currencyCode"],
          type: transaction["type"],
          balance: transaction.dig("balance", "amount"),
          createdDateTime: transaction["createdDateTime"],
        }
      end
    end

    def logout
      @logger.info "Logging out"
      response = @client.get("https://secure.anz.co.nz/IBCS/service/goodbye")
      if response.status != 200
        raise "Error logging out: #{response.status}\n\n#{response.body}"
      end
    end

    private

    # Method to convert a base64 encoded key into PEM format
    def convert_to_pem_format(key_str)
      trimmed_key = key_str.strip

      header = "-----BEGIN PUBLIC KEY-----"
      footer = "-----END PUBLIC KEY-----"

      # Split the key into 64-character lines
      split_lines = trimmed_key.scan(/.{1,64}/).join("\n")
      "#{header}\n#{split_lines}\n#{footer}"
    end

    def encrypt_password(password)
      # Convert the key to PEM format
      pem_formatted_key = convert_to_pem_format(@encryption_key)

      # Create a public key object from the PEM-formatted string
      public_key = OpenSSL::PKey::RSA.new(pem_formatted_key)

      # Encrypt the message using the public key and PKCS1 padding
      encrypted_password = public_key.public_encrypt(password, OpenSSL::PKey::RSA::PKCS1_PADDING)

      # Encode the encrypted message with base64
      ::Base64.encode64(encrypted_password).gsub("\n", "")
    end
  end
end
