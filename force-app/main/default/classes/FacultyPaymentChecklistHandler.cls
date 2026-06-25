/**
 * @description Handler for payment-related automation around course manager assignment
 * and Payment Information lifecycle updates.
 */
public class FacultyPaymentChecklistHandler {
    

	/**
	 * @description Handles after insert trigger on course_managers__c
	 * Updates Payment Information SPOC mapping for delivery manager assignments.
	 */
	public static void handleAfterInsert(List<course_managers__c> newManagers) {
		assignSPOCFromDeliveryManager(newManagers);
	}

	// Static set to prevent recursion
	private static Set<Id> processedPaymentIds = new Set<Id>();

	// Cache for queue IDs to avoid repeated queries
	private static Map<String, Id> queueIdCache = new Map<String, Id>();

	/**
	 * @description Maps Payment Information status values to numeric order for validation.
	 * @param status The status picklist value
	 * @return Integer representing status order (0-5), or -1 if unknown
	 */
	private static Integer getStatusOrder(String status) {
		Map<String, Integer> statusOrder = new Map<String, Integer> {
			'Draft' => 0,
			'Grades Released' => 1,
			'ASA Processing' => 2,
			'Submitted to Finance' => 3,
			'Finance Processing' => 4,
			'Completed' => 5
		};
		return statusOrder.containsKey(status) ? statusOrder.get(status) : -1;
	}

	/**
	 * @description Retrieves queue IDs by queue names.
	 * Caches results to minimize SOQL queries.
	 * @param queueNames Set of queue developer names (e.g., 'ASA_Queue', 'Finance_Team')
	 * @return Map of queue name to queue ID
	 */
	private static Map<String, Id> getQueueIds(Set<String> queueNames) {
		Set<String> queuesToQuery = new Set<String>();

		// Only query for queues not already in cache
		for (String queueName : queueNames) {
			if (!queueIdCache.containsKey(queueName)) {
				queuesToQuery.add(queueName);
			}
		}

		if (!queuesToQuery.isEmpty()) {
			try {
				List<Group> queues = [
					SELECT Id, DeveloperName
					FROM Group
					WHERE Type = 'Queue'
					  AND DeveloperName IN :queuesToQuery
				];

				for (Group queue : queues) {
					queueIdCache.put(queue.DeveloperName, queue.Id);
				}
			} catch (Exception e) {
				System.debug('Error retrieving queue IDs: ' + e.getMessage());
			}
		}

		return queueIdCache;
	}

	/**
	 * @description Assigns a Payment_Information record to a queue or user.
	 * When assigning to a queue, all queue members can accept the record.
	 * @param payment The Payment_Information record to update
	 * @param targetQueueName The queue developer name (e.g., 'ASA_Queue', 'Finance_Team')
	 */
	private static void assignToQueue(Payment_Information__c payment, String targetQueueName) {
		Map<String, Id> queueIds = getQueueIds(new Set<String> {targetQueueName});

		if (queueIds.containsKey(targetQueueName)) {
			payment.OwnerId = queueIds.get(targetQueueName);
		} else {
			System.debug('Queue not found: ' + targetQueueName);
		}
	}

	/**
	 * @description Assigns a Payment_Information record to a specific user.
	 * @param payment The Payment_Information record to update
	 * @param userId The Salesforce user ID
	 */
	private static void assignToUser(Payment_Information__c payment, Id userId) {
		if (userId != null) {
			payment.OwnerId = userId;
		}
	}

	/**
	 * @description When a Delivery Manager is added to a Course Offering, sets SPOC__c
	 * on all Payment_Information__c records under that Course Offering to that user.
	 * Overwrites any existing SPOC__c value.
	 */
	private static void assignSPOCFromDeliveryManager(List<course_managers__c> newManagers) {
		Map<Id, Id> offeringToSPOC = new Map<Id, Id>();

		for (course_managers__c mgr : newManagers) {
			if (mgr.Role__c == 'Delivery Manager'
				&& mgr.User__c != null
				&& mgr.Course_Offering__c != null) {
				offeringToSPOC.put(mgr.Course_Offering__c, mgr.User__c);
			}
		}

		if (offeringToSPOC.isEmpty()) {
			return;
		}

		List<Payment_Information__c> paymentsToUpdate = new List<Payment_Information__c>();

		for (Payment_Information__c pi : [
			SELECT Id, SPOC__c, Course_Offering__c
			FROM Payment_Information__c
			WHERE Course_Offering__c IN :offeringToSPOC.keySet()
		]) {
			pi.SPOC__c = offeringToSPOC.get(pi.Course_Offering__c);
			paymentsToUpdate.add(pi);
		}

		if (!paymentsToUpdate.isEmpty()) {
			update paymentsToUpdate;
			System.debug('Assigned SPOC to ' + paymentsToUpdate.size() + ' Payment Information records for Delivery Manager assignment.');
		}
	}

	/**
	 * @description Handles Payment_Information__c lifecycle automation.
	 * Early stage flow: Draft -> Course Manager assigned (owner becomes manager) ->
	 * Grade Release Date entered (auto checks Grades Released and updates status).
	 *
	 * @param newPayments List of new/updated Payment_Information__c records
	 * @param oldMap Map of old Payment_Information__c records (null for insert)
	 */
	public static void handleGradesReleasedLogic(
		List<Payment_Information__c> newPayments,
		Map<Id, Payment_Information__c> oldMap
	) {
		Map<Id, Payment_Information__c> cloneSourceById = new Map<Id, Payment_Information__c>();
		if (oldMap == null) {
			Set<Id> cloneSourceIds = new Set<Id>();
			for (Payment_Information__c payment : newPayments) {
				if (payment.isClone() && payment.getCloneSourceId() != null) {
					cloneSourceIds.add(payment.getCloneSourceId());
				}
			}

			if (!cloneSourceIds.isEmpty()) {
				for (Payment_Information__c sourcePayment : [
					SELECT Id, Remuneration_Type__c, Course_Offering__c, Faculty__c
					FROM Payment_Information__c
					WHERE Id IN :cloneSourceIds
				]) {
					cloneSourceById.put(sourcePayment.Id, sourcePayment);
				}
			}
		}

		for (Payment_Information__c payment : newPayments) {
			Payment_Information__c oldPayment = oldMap != null ? oldMap.get(payment.Id) : null;
			Boolean isCloneInsert = oldPayment == null && payment.isClone();

			if (isCloneInsert) {
				Id sourceId = payment.getCloneSourceId();
				if (sourceId != null && cloneSourceById.containsKey(sourceId)) {
					Payment_Information__c sourcePayment = cloneSourceById.get(sourceId);

					// Ensure cloned records carry source context fields.
					payment.Course_Offering__c = sourcePayment.Course_Offering__c;
					payment.Faculty__c = sourcePayment.Faculty__c;

					if (sourcePayment.Remuneration_Type__c == payment.Remuneration_Type__c) {
						payment.Remuneration_Type__c.addError('Cloned records must use a different remuneration type than the source record.');
					}
				}

				// Cloned records must always restart from Draft.
				payment.Status__c = 'Draft';
				payment.Grade_Release_Date__c = null;
				payment.Grades_Released__c = false;
				payment.ASA_Ready_for_Finance__c = false;
				payment.Submitted_to_Finance__c = false;
				payment.Sent_to_Finance_Date__c = null;
			}

			// Handle SPOC assignment - change owner to SPOC
			Boolean spocAssignedNow = payment.SPOC__c != null
				&& (oldPayment == null || oldPayment.SPOC__c != payment.SPOC__c);

			if (spocAssignedNow) {
				assignToUser(payment, payment.SPOC__c);
			}

			// Handle Course Manager assignment - change owner to Course Manager
			// This runs only if SPOC was not just assigned (SPOC takes precedence)
			Boolean courseManagerAssignedNow = payment.Course_Manager__c != null
				&& (oldPayment == null || oldPayment.Course_Manager__c != payment.Course_Manager__c)
				&& !spocAssignedNow;

			if (courseManagerAssignedNow) {
				assignToUser(payment, payment.Course_Manager__c);
			}

			// Course Manager must be assigned before any grade release action.
			if ((payment.Grade_Release_Date__c != null || payment.Grades_Released__c)
				&& payment.SPOC__c == null) {
				payment.Grade_Release_Date__c.addError('Please select a SPOC before releasing grades.');
				continue;
			}

			if (payment.Grade_Release_Date__c != null) {
				payment.Grades_Released__c = true;
				if (!isCloneInsert
					&& oldPayment == null
					&& (String.isBlank(payment.Status__c) || payment.Status__c == 'Draft')) {
					payment.Status__c = 'Grades Released';
				}
			}

			if (oldPayment == null) {
				continue;
			}

			// Skip if already processed in this transaction (recursion guard)
			if (payment.Id != null && processedPaymentIds.contains(payment.Id)) {
				continue;
			}

			if (payment.Id != null) {
				processedPaymentIds.add(payment.Id);
			}

			Boolean gradesJustReleased = payment.Grades_Released__c && !oldPayment.Grades_Released__c;
			Boolean asaReadyNow = payment.ASA_Ready_for_Finance__c && !oldPayment.ASA_Ready_for_Finance__c;
			Boolean submittedNow = payment.Submitted_to_Finance__c && !oldPayment.Submitted_to_Finance__c;
			Boolean paymentStatusChanged = payment.Payment_Status__c != oldPayment.Payment_Status__c;
			Boolean closureStatusSetToClosed = payment.Closure_Status__c == 'Closed' && oldPayment.Closure_Status__c != 'Closed';
			Boolean closureStatusSetToRejected = payment.Closure_Status__c == 'Rejected' && oldPayment.Closure_Status__c != 'Rejected';
			Boolean wasCompletedBeforeUpdate = oldPayment.Status__c == 'Completed' || oldPayment.Payment_Status__c == 'Completed';

			if (closureStatusSetToClosed && payment.Payment_Status__c != 'Completed') {
				payment.Closure_Status__c.addError('Cannot set Closure Status to Closed unless Payment Status is Completed.');
				continue;
			}

			if (closureStatusSetToRejected && wasCompletedBeforeUpdate) {
				payment.Closure_Status__c.addError('Cannot set Closure Status to Rejected after payment is completed.');
				continue;
			}

			if (gradesJustReleased && oldPayment.Status__c == 'Draft') {
				payment.Status__c = 'Grades Released';
			}

			// Handle Closure Status rejection - send back to ASA Processing with SPOC as owner.
			if (closureStatusSetToRejected) {
				payment.Status__c = 'ASA Processing';
				payment.ASA_Ready_for_Finance__c = false;
				payment.Submitted_to_Finance__c = false;
				if (payment.SPOC__c != null) {
					assignToUser(payment, payment.SPOC__c);
				}
			}

			if (asaReadyNow) {
				payment.Submitted_to_Finance__c = true;
				if (payment.Sent_to_Finance_Date__c == null) {
					payment.Sent_to_Finance_Date__c = Date.today();
				}
				payment.Status__c = 'Submitted to Finance';
			}

			if (paymentStatusChanged) {
				// Stage 5: Finance Processing - triggered when Payment_Status__c is set to 'In Progress'
				if (payment.Payment_Status__c == 'In Progress' && oldPayment.Payment_Status__c != 'In Progress') {
					payment.Status__c = 'Finance Processing';
				}
				// Stage 6: Completed - auto-set Closure Status to Closed and Status to Completed.
				// Validation rules enforce that Final Remarks, Transaction ID, and Payment Date are filled.
				else if (payment.Payment_Status__c == 'Completed' && oldPayment.Payment_Status__c != 'Completed') {
					payment.Closure_Status__c = 'Closed';
					payment.Status__c = 'Completed';
					payment.Payment_Done__c = true;
				}
			}

			// Prevent ownership changes when status is moving backward.
			// This prevents "insufficient access rights" error from firing before validation rules.
			Boolean isMovingBackward = false;
			if (payment.Status__c != oldPayment.Status__c) {
				Integer oldStatusOrder = getStatusOrder(oldPayment.Status__c);
				Integer newStatusOrder = getStatusOrder(payment.Status__c);
				if (oldStatusOrder >= 0 && newStatusOrder >= 0 && newStatusOrder < oldStatusOrder) {
					isMovingBackward = true;
				}
			}

			// If transitioning to "Submitted to Finance" (and not moving backward), assign to Finance_Team queue.
			if (!isMovingBackward && payment.Status__c == 'Submitted to Finance' && oldPayment.Status__c != 'Submitted to Finance') {
				assignToQueue(payment, 'Finance_Team');
			}
	}
	}

	/**
	 * @description Handles owner change notifications for Payment Information records.
	 * Sends in-app bell icon notifications to the new owner when ownership changes.
	 * If the new owner is a queue, notifies all queue members.
	 * 
	 * @param newPayments List of updated Payment_Information__c records
	 * @param oldMap Map of old Payment_Information__c records before update
	 */
	public static void handleOwnerChangeNotifications(
		List<Payment_Information__c> newPayments,
		Map<Id, Payment_Information__c> oldMap
	) {
		System.debug('=== handleOwnerChangeNotifications START ===');
		System.debug('Records to process: ' + newPayments.size());
		System.debug('Context: ' + (oldMap == null ? 'AFTER INSERT' : 'AFTER UPDATE'));
		
		// Track owner changes
		List<Payment_Information__c> changedOwners = new List<Payment_Information__c>();
		Set<Id> newOwnerIds = new Set<Id>();
		
		for (Payment_Information__c payment : newPayments) {
			System.debug('Checking record: ' + payment.Id);
			System.debug('  New Owner: ' + payment.OwnerId);
			
			boolean shouldNotify = false;
			
			if (oldMap == null) {
				// AFTER INSERT: Send notification if owner is assigned
				if (payment.OwnerId != null) {
					System.debug('  ✓ After insert with owner assigned - adding to notification list');
					shouldNotify = true;
				} else {
					System.debug('  × After insert but no owner assigned - skipping');
				}
			} else {
				// AFTER UPDATE: Send notification if owner changed
				Payment_Information__c oldPayment = oldMap.get(payment.Id);
				System.debug('  Old Owner: ' + oldPayment.OwnerId);
				
				if (payment.OwnerId != null && payment.OwnerId != oldPayment.OwnerId) {
					System.debug('  ✓ Owner changed - adding to notification list');
					shouldNotify = true;
				} else {
					System.debug('  × Owner unchanged - skipping');
				}
			}
			
			if (shouldNotify) {
				changedOwners.add(payment);
				newOwnerIds.add(payment.OwnerId);
			}
		}
		
		System.debug('Total owner assignments/changes detected: ' + changedOwners.size());
		
		if (changedOwners.isEmpty()) {
			System.debug('No owner changes detected. Exiting.');
			return;
		}
		
		// Get Custom Notification Type
		String notifTypeId;
		List<CustomNotificationType> notifTypes = [
			SELECT Id, DeveloperName
			FROM CustomNotificationType
			WHERE DeveloperName = 'Payment_Information_Assignment'
			LIMIT 1
		];
		
		System.debug('Looking for Custom Notification Type: Payment_Information_Assignment');
		
		if (notifTypes.isEmpty()) {
			System.debug('Payment_Information_Assignment not found. Trying fallback...');
			// Fallback: get any custom notification type
			notifTypes = [
				SELECT Id FROM CustomNotificationType LIMIT 1
			];
		}
		
		if (notifTypes.isEmpty()) {
			System.debug(LoggingLevel.ERROR, 'ERROR: No Custom Notification Type found. Please create one to enable notifications.');
			return;
		}
		
		notifTypeId = notifTypes[0].Id;
		System.debug('✓ Using Custom Notification Type ID: ' + notifTypeId);
		
		// Query to determine if new owners are users or queues
		Map<Id, User> userOwners = new Map<Id, User>();
		Map<Id, Group> queueOwners = new Map<Id, Group>();
		Map<Id, Set<Id>> queueMembersByQueueId = new Map<Id, Set<Id>>();
		
		// Query users
		List<User> users = [
			SELECT Id, Name
			FROM User
			WHERE Id IN :newOwnerIds
		];
		for (User u : users) {
			userOwners.put(u.Id, u);
		}
		
		// Query queues
		List<Group> queues = [
			SELECT Id, Name, DeveloperName
			FROM Group
			WHERE Id IN :newOwnerIds AND Type = 'Queue'
		];
		for (Group q : queues) {
			queueOwners.put(q.Id, q);
		}
		
		// Query queue members if any queues found
		if (!queueOwners.isEmpty()) {
			List<GroupMember> queueMembers = [
				SELECT GroupId, UserOrGroupId
				FROM GroupMember
				WHERE GroupId IN :queueOwners.keySet()
			];
			
			for (GroupMember gm : queueMembers) {
				if (!queueMembersByQueueId.containsKey(gm.GroupId)) {
					queueMembersByQueueId.put(gm.GroupId, new Set<Id>());
				}
				queueMembersByQueueId.get(gm.GroupId).add(gm.UserOrGroupId);
			}
			
			// Query user details for all queue members
			Set<Id> allMemberUserIds = new Set<Id>();
			for (Set<Id> memberIds : queueMembersByQueueId.values()) {
				allMemberUserIds.addAll(memberIds);
			}
			
			if (!allMemberUserIds.isEmpty()) {
				List<User> queueMemberUsers = [
					SELECT Id, Name
					FROM User
					WHERE Id IN :allMemberUserIds
				];
				for (User u : queueMemberUsers) {
					userOwners.put(u.Id, u);
				}
			}
		}
		
		// Send Custom Notifications (Bell Icon)
		Integer notificationCount = 0;
		Set<String> notificationKeys = new Set<String>();
		
		System.debug('Starting to send notifications...');
		
		for (Payment_Information__c payment : changedOwners) {
			String recordName = payment.Name != null ? payment.Name : 'Payment Information';
			
			System.debug('Processing notification for: ' + recordName + ' (ID: ' + payment.Id + ')');
			System.debug('  New Owner ID: ' + payment.OwnerId);
			
			// Check if new owner is a user
			if (userOwners.containsKey(payment.OwnerId)) {
				User newOwner = userOwners.get(payment.OwnerId);
				String notifKey = String.valueOf(payment.OwnerId) + '|' + String.valueOf(payment.Id);
				
				System.debug('  Owner is a USER: ' + newOwner.Name);
				
				if (!notificationKeys.contains(notifKey)) {
					try {
						System.debug('  Sending notification to: ' + newOwner.Name + ' (' + payment.OwnerId + ')');
						Messaging.CustomNotification notification = new Messaging.CustomNotification();
						notification.setNotificationTypeId(notifTypeId);
						notification.setTargetId(payment.Id);
						notification.setTitle('Payment Information Assigned');
						notification.setBody('Payment Information ' + recordName + ' has been assigned to you. Please review and take necessary action.');
						notification.send(new Set<String>{ String.valueOf(payment.OwnerId) });
						notificationKeys.add(notifKey);
						notificationCount++;
						System.debug('  ✓ Notification sent successfully');
					} catch (Exception e) {
						System.debug(LoggingLevel.ERROR, '  × Error sending notification to user ' + newOwner.Name + ': ' + e.getMessage());
						System.debug(LoggingLevel.ERROR, '  Stack trace: ' + e.getStackTraceString());
					}
				} else {
					System.debug('  × Duplicate notification key - skipping');
				}
			}
			// Check if new owner is a queue
			else if (queueOwners.containsKey(payment.OwnerId)) {
				Group queue = queueOwners.get(payment.OwnerId);
				Set<Id> memberIds = queueMembersByQueueId.get(payment.OwnerId);
				
				System.debug('  Owner is a QUEUE: ' + queue.Name);
				System.debug('  Queue has ' + (memberIds != null ? memberIds.size() : 0) + ' member(s)');
				
				if (memberIds != null && !memberIds.isEmpty()) {
					for (Id memberId : memberIds) {
						if (userOwners.containsKey(memberId)) {
							User member = userOwners.get(memberId);
							String notifKey = String.valueOf(memberId) + '|' + String.valueOf(payment.Id);
							
							System.debug('    Sending notification to queue member: ' + member.Name);
							
							if (!notificationKeys.contains(notifKey)) {
								try {
									Messaging.CustomNotification notification = new Messaging.CustomNotification();
									notification.setNotificationTypeId(notifTypeId);
									notification.setTargetId(payment.Id);
									notification.setTitle('Payment Information Assigned to ' + queue.Name);
									notification.setBody('Payment Information ' + recordName + ' has been assigned to the ' + queue.Name + ' queue. You can review and accept this record.');
									notification.send(new Set<String>{ String.valueOf(memberId) });
									notificationKeys.add(notifKey);
									notificationCount++;
									System.debug('    ✓ Notification sent to ' + member.Name);
								} catch (Exception e) {
									System.debug(LoggingLevel.ERROR, '    × Error sending notification to queue member ' + member.Name + ': ' + e.getMessage());
									System.debug(LoggingLevel.ERROR, '    Stack trace: ' + e.getStackTraceString());
								}
							} else {
								System.debug('    × Duplicate notification key - skipping');
							}
						}
					}
				}
			} else {
				System.debug('  × Owner not found in users or queues');
			}
		}
		
		System.debug('=== NOTIFICATION SUMMARY ===');
		System.debug('Total notifications sent: ' + notificationCount);
		System.debug('=== handleOwnerChangeNotifications END ===');
		
		if (notificationCount > 0) {
			System.debug('✓ Sent ' + notificationCount + ' bell icon notification(s) for Payment Information owner changes.');
		}
	}

}