module Types
  class RacerStatusChangeEnum < BaseEnum
    graphql_name "RacerStatusChange"
    value "DNF", "Did not finish", value: "dnf"
    value "DNS", "Did not start", value: "dns"
    value "DSQ", "Disqualified", value: "dsq"
    value "NONE", "Clear a DNF/DNS/DSQ: status follows the crossings again", value: nil
  end
end
