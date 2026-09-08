int long_nested_condition(
	int primary_connection_address_matches_expected,
	int supplied_client_identifier_matches_expected,
	int supplied_network_port_matches_expected,
	int stored_network_port_matches_expected,
	int secondary_connection_address_matches_expected) {
	// displayed_result = left_value + right_value;
	// displayed_result += right_value;
	if (primary_connection_address_matches_expected != 0 &&
		(supplied_client_identifier_matches_expected != 0 ||
			(supplied_network_port_matches_expected == stored_network_port_matches_expected &&
				secondary_connection_address_matches_expected != 0))) {
		return 1;
	}
	return 0;
}
