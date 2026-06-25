const fs = require('fs');

function fixFlow(filePath) {
    let content = fs.readFileSync(filePath, 'utf8');

    // Add IsChanged conditions to Decision rules
    const rulesToFix = ['Operations_Changed', 'IT_Changed', 'LRC_Changed', 'ASA_SA_Changed', 'Finance_Changed'];
    
    for (let rule of rulesToFix) {
        // Regex to find the <conditions> block for each rule and add IsChanged if not present
        const ruleRegex = new RegExp(`(<name>${rule}</name>\\s*<conditionLogic>and</conditionLogic>\\s*<conditions>[\\s\\S]*?<rightValue>[\\s\\S]*?</rightValue>\\s*</conditions>)`);
        
        let match = content.match(ruleRegex);
        if (match) {
            let conditionBlock = match[1];
            // Extract the leftValueReference to reuse it
            let fieldMatch = conditionBlock.match(/<leftValueReference>(.*?)<\/leftValueReference>/);
            if (fieldMatch) {
                let field = fieldMatch[1];
                let newCondition = `
            <conditions>
                <leftValueReference>${field}</leftValueReference>
                <operator>IsChanged</operator>
                <rightValue>
                    <booleanValue>true</booleanValue>
                </rightValue>
            </conditions>`;
                
                // Add it after the existing condition if it doesn't already have IsChanged
                if (!conditionBlock.includes('<operator>IsChanged</operator>')) {
                    content = content.replace(conditionBlock, conditionBlock + newCondition);
                }
            }
        }
    }
    
    // We should also change the flow to be sequential to support multiple flags at once.
    // However, that requires creating new Decision nodes and rewiring connectors.
    // Let's first just fix the IsChanged bug, as that's the most glaring issue causing the reported bug.
    
    fs.writeFileSync(filePath, content);
    console.log(`Fixed ${filePath}`);
}

fixFlow('force-app/main/default/flows/Operations_IT_LRC_Clearance_AutoStamp_Flow.flow-meta.xml');
fixFlow('force-app/main/default/flows/Outgoing_Clearance_AutoStamp_Flow.flow-meta.xml');
