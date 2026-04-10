module NbaStats
  module TeamCodes
    ALL = %w[
      ATL BOS BKN CHA CHI CLE DAL DEN DET GSW HOU IND LAC LAL MEM MIA MIL
      MIN NOP NYK OKC ORL PHI PHX POR SAC SAS TOR UTA WAS
    ].freeze

    TEAM_ID_TO_ABBR = {
      16_106_127_37 => 'ATL',
      16_106_127_38 => 'BOS',
      16_106_127_39 => 'CLE',
      16_106_127_40 => 'NOP',
      16_106_127_41 => 'CHI',
      16_106_127_42 => 'DAL',
      16_106_127_43 => 'DEN',
      16_106_127_44 => 'GSW',
      16_106_127_45 => 'HOU',
      16_106_127_46 => 'LAC',
      16_106_127_47 => 'LAL',
      16_106_127_48 => 'MIA',
      16_106_127_49 => 'MIL',
      16_106_127_50 => 'MIN',
      16_106_127_51 => 'BKN',
      16_106_127_52 => 'NYK',
      16_106_127_53 => 'ORL',
      16_106_127_54 => 'IND',
      16_106_127_55 => 'PHI',
      16_106_127_56 => 'PHX',
      16_106_127_57 => 'POR',
      16_106_127_58 => 'SAC',
      16_106_127_59 => 'SAS',
      16_106_127_60 => 'OKC',
      16_106_127_61 => 'TOR',
      16_106_127_62 => 'UTA',
      16_106_127_63 => 'MEM',
      16_106_127_64 => 'WAS',
      16_106_127_65 => 'DET',
      16_106_127_66 => 'CHA'
    }.freeze
  end
end
