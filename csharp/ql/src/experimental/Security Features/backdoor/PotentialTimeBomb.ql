/**
 * @name Potential Timebomb
 * @description Flow from a file last modification date (very likely implant installation time) and an offset to condition statement (the trigger)
 * @kind problem
 * @precision Low
 * @problem.severity warning
 * @id cs/backdoor/potential-time-bomb
 * @tags security
 *       solorigate
 */

import csharp
import DataFlow

/**
 * Class that will help to find the source for the trigger file-modification date.
 * 
 * May be extended as new patterns for similar time bombs are found.
 */
class GetLastWriteTimeMethod extends Method {
	GetLastWriteTimeMethod() {
		this.getQualifiedName() in [ "System.IO.File.GetLastWriteTime", "System.IO.File.GetFileCreationTime", "System.IO.File.GetCreationTimeUtc", "System.IO.File.GetLastAccessTimeUtc" ]
	}
}

/**
 * Abstracts `System.DateTime` structure
 */
class DateTimeStruct extends Struct {
	DateTimeStruct() {
		this.getQualifiedName() = "System.DateTime"
	}
	
	/**
	 * holds if the Callable is used for DateTime arithmetic operations
	 */
	Callable getATimeSpanArtithmeticCallable() {
		( result = this.getAnOperator() or result = this.getAMethod()) and
		( result.getName() in ["Add", "AddDays", "AddHours", "AddMilliseconds", "AddMinutes", "AddMonths", "AddSeconds", "AddTicks", "AddYears", "+", "-"] )
	}

	/**
	 * Holds if the Callable is used for DateTime comparision
	 */
	Callable getAComparisonCallable() {
		( result = this.getAnOperator() or result = this.getAMethod()) and
		( result.getName() in ["Compare", "CompareTo", "Equals", "==", "!=", "<", ">", "<=", ">="] )
	}
}

/**
 * Dataflow configuration to find flow from a GetLastWriteTime source to a DateTime arithmetic operation 
 */
private class FlowsFromGetLastWriteTimeConfigToTimeSpanArithmeticCallable extends TaintTracking::Configuration {
  FlowsFromGetLastWriteTimeConfigToTimeSpanArithmeticCallable() {
    this = "FlowsFromGetLastWriteTimeConfigToTimeSpanArithmeticCallable"
  }

  override
  predicate isSource(DataFlow::Node source) {
    exists( Call call, GetLastWriteTimeMethod m |
    	m.getACall() = call and
    	source.asExpr() = call
    )
  }

  override
  predicate isSink(DataFlow::Node sink) {
    exists( Call call, DateTimeStruct dateTime |
    	call.getAChild*() = sink.asExpr() and
    	call = dateTime.getATimeSpanArtithmeticCallable().getACall()
    )
  }
}

/**
 * Dataflow configuration to find flow from a DateTime arithmetic operation to a DateTime comparison operation 
 */
private class FlowsFromTimeSpanArithmeticToTimeComparisonCallable extends TaintTracking::Configuration {
  FlowsFromTimeSpanArithmeticToTimeComparisonCallable() {
    this = "FlowsFromTimeSpanArithmeticToTimeComparisonCallable"
  }

  override
  predicate isSource(DataFlow::Node source) {
    exists( DateTimeStruct dateTime, Call call |
    	source.asExpr() = call | 
    	call = dateTime.getATimeSpanArtithmeticCallable().getACall()
    )
  }

  override
  predicate isSink(DataFlow::Node sink) {
    exists( Call call, DateTimeStruct dateTime |
    	call.getAnArgument().getAChild*() = sink.asExpr() and
    	call = dateTime.getAComparisonCallable().getACall()
    )
  
  }
}

/**
 * Dataflow configuration to find flow from a DateTime comparison operation to a Selection Statement (such as an If) 
 */
private class FlowsFromTimeComparisonCallableToSelectionStatementCondition extends TaintTracking::Configuration {
  FlowsFromTimeComparisonCallableToSelectionStatementCondition() {
    this = "FlowsFromTimeComparisonCallableToSelectionStatementCondition"
  }

  override
  predicate isSource(DataFlow::Node source) {
    exists( DateTimeStruct dateTime, Call call |
    	source.asExpr() = call | 
    	call = dateTime.getAComparisonCallable().getACall()
    )
  }

  override
  predicate isSink(DataFlow::Node sink) {
    exists( SelectionStmt sel |
    	sel.getCondition().getAChild*() = sink.asExpr()
    )
  
  }
}

/**
 * Holds if the last file modification date from the call to getLastWriteTimeMethodCall will be used in a DateTime arithmetic operation timeArithmeticCall,
 * which is then used for a DateTime comparison timeComparisonCall and the result flows to a Selection statement which is likely a TimeBomb trigger 
 */
predicate isPotentialTimeBomb( Call getLastWriteTimeMethodCall, Call timeArithmeticCall, Call timeComparisonCall, SelectionStmt selStatement ) {
	exists( FlowsFromGetLastWriteTimeConfigToTimeSpanArithmeticCallable config1, Node sink, DateTimeStruct dateTime,
			FlowsFromTimeSpanArithmeticToTimeComparisonCallable config2, Node sink2,
			FlowsFromTimeComparisonCallableToSelectionStatementCondition config3, Node sink3 |
  	  	config1.hasFlow(exprNode(getLastWriteTimeMethodCall), sink) and 
		timeArithmeticCall = dateTime.getATimeSpanArtithmeticCallable().getACall() and
		timeArithmeticCall.getAChild*() = sink.asExpr() and 
		config2.hasFlow(exprNode(timeArithmeticCall), sink2) and 
		timeComparisonCall = dateTime.getAComparisonCallable().getACall() and 
		timeComparisonCall.getAnArgument().getAChild*() = sink2.asExpr() and
		config3.hasFlow(exprNode(timeComparisonCall), sink3) and
		selStatement.getCondition().getAChild*() = sink3.asExpr()
	)
}

from Call getLastWriteTimeMethodCall, Call timeArithmeticCall, Call timeComparisonCall, SelectionStmt selStatement
where isPotentialTimeBomb( getLastWriteTimeMethodCall, timeArithmeticCall, timeComparisonCall, selStatement )
select selStatement, "Possible TimeBomb logic triggered by $@ that takes into account $@ from the $@ as part of the potential trigger."
	, timeComparisonCall, timeComparisonCall.toString() 
 	, timeArithmeticCall, "an offset"
   	,getLastWriteTimeMethodCall, "last modification time of a file"
 

