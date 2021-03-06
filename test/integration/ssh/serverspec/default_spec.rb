require 'serverspec'
require 'json'

set :backend, :exec

describe 'sftp node' do
  let(:node) do
    JSON.parse(
      IO.read(File.join(ENV['TEMP'] || '/tmp', 'kitchen/sftp.json'))
    )
  end
  let(:ip) { node['automatic']['ipaddress'] }
  let(:fqdn) { node['automatic']['fqdn'] }
  let(:connection) do
    Net::SSH.start(
      ip,
      'vagrant',
      password: 'vagrant',
      paranoid: false
    )
  end

  it 'has an non localhost ip' do
    expect(ip).not_to eq('127.0.0.1')
  end

  it 'has a valid ip' do
    expect(ip).to match(/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/)
  end

  describe command('hostname') do
    its(:stdout) { should_not match(/#{Regexp.quote(fqdn)}/) }
  end

  it 'has a computername matching node fqdn' do
    connection.open_channel do |channel|
      channel.request_pty
      channel.exec('hostname') do |_ch, _success|
        channel.on_data do |_ch, data|
          expect(data.chomp).to eq(fqdn)
        end
      end
    end
    connection.loop
  end
end
