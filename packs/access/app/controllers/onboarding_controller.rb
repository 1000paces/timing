# Served over plain HTTP so a new tablet can fetch and trust the hub's CA.
class OnboardingController < ApplicationController
  class_attribute :local_ca

  def show
    render body: page, content_type: "text/html"
  end

  def ca
    return head :not_found unless ca_store.root_cert_path.exist?
    send_data ca_store.root_cert_path.read, type: "application/x-x509-ca-cert", filename: "timing-hub-ca.crt"
  end

  private

  def ca_store = self.class.local_ca || LocalCa.new

  def page
    port = ENV.fetch("HUB_TLS_PORT", "3443")
    urls = (LocalCa.lan_ips.presence || ["127.0.0.1"]).map { "https://#{it}:#{port}" }
    fingerprint = ca_store.root_cert_path.exist? ? ca_store.root_fingerprint : "unavailable"
    <<~HTML
      <!doctype html>
      <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Set up this device</title>
      <style>body{font:16px/1.5 system-ui,sans-serif;max-width:40rem;margin:2rem auto;padding:0 1rem}a{word-break:break-all}</style></head>
      <body>
        <h1>Set up this device for the timing hub</h1>
        <ol>
          <li><a href="/onboarding/ca.crt">Download the hub certificate</a>.</li>
          <li><strong>iPhone/iPad:</strong> Settings → Profile Downloaded → Install. Then Settings → General → About →
              Certificate Trust Settings → turn on “Timing Hub Local CA”.</li>
          <li><strong>Android:</strong> Settings → Security → Encryption &amp; credentials → Install a certificate → CA certificate.</li>
          <li>Open the hub: #{urls.map { "<a href=\"#{ERB::Util.h(it)}\">#{ERB::Util.h(it)}</a>" }.join(' or ')}</li>
        </ol>
        <p>Check this fingerprint matches the one shown on the hub screen:<br>
           <code>#{ERB::Util.h(fingerprint)}</code></p>
      </body></html>
    HTML
  end
end
