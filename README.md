# Tokenized Decentralized Plumbing Emergency Networks

A comprehensive blockchain-based system for managing plumbing emergencies, leak detection, parts inventory, and preventive maintenance using Clarity smart contracts.

## System Overview

This decentralized network consists of five interconnected smart contracts that work together to provide a complete plumbing emergency management solution:

### Core Contracts

1. **Leak Detection Contract** (`leak-detection.clar`)
    - Monitors water pressure across the network
    - Identifies pipe failures and anomalies
    - Records leak incidents with severity levels
    - Tracks sensor data and maintenance history

2. **Emergency Response Contract** (`emergency-response.clar`)
    - Coordinates rapid plumber dispatch for urgent issues
    - Manages emergency request queue and prioritization
    - Tracks response times and completion status
    - Handles emergency escalation procedures

3. **Parts Inventory Contract** (`parts-inventory.clar`)
    - Manages availability of common plumbing components
    - Tracks inventory levels and supplier information
    - Handles parts reservation and allocation
    - Monitors usage patterns and restocking needs

4. **Cost Estimation Contract** (`cost-estimation.clar`)
    - Provides transparent pricing for repair services
    - Calculates costs based on parts, labor, and complexity
    - Maintains pricing history and market rates
    - Supports dynamic pricing based on demand

5. **Prevention Monitoring Contract** (`prevention-monitoring.clar`)
    - Tracks system health to prevent major failures
    - Schedules preventive maintenance activities
    - Monitors performance metrics and trends
    - Generates maintenance recommendations

## Key Features

- **Decentralized Architecture**: No single point of failure
- **Transparent Pricing**: All costs are recorded on-chain
- **Real-time Monitoring**: Continuous system health tracking
- **Emergency Prioritization**: Automated dispatch based on severity
- **Inventory Management**: Efficient parts tracking and allocation
- **Preventive Maintenance**: Proactive system health management

## Token Economics

The system uses utility tokens for:
- Service payments and deposits
- Staking for service providers
- Governance and voting rights
- Incentivizing network participation

## Getting Started

### Prerequisites
- Clarity development environment
- Stacks blockchain testnet access
- Node.js for testing

### Installation
1. Clone the repository
2. Install dependencies: \`npm install\`
3. Run tests: \`npm test\`
4. Deploy contracts to testnet

### Testing
The project includes comprehensive Vitest test suites for all contracts:
- Unit tests for individual contract functions
- Integration tests for contract interactions
- Edge case and error handling tests

## Contract Architecture

Each contract is designed to be self-contained while contributing to the overall network functionality:

- **Data Storage**: Efficient use of Clarity data structures
- **Access Control**: Role-based permissions and authorization
- **Error Handling**: Comprehensive error responses and validation
- **Event Logging**: Detailed transaction and state change tracking

## Security Considerations

- Input validation on all public functions
- Access control for administrative functions
- Safe arithmetic operations to prevent overflow
- Proper error handling and recovery mechanisms

## Contributing

Please read the PR details file for contribution guidelines and development standards.

## License

This project is licensed under the MIT License.
