import ceylon.time.base { Range, milliseconds, UnitOfDate, days }
import ceylon.time.internal { previousByStep, nextByStep, gapUtil = gap, overlapUtil = overlap }

see( Range )
shared class DateRange( from, to, step = days ) satisfies Range<Date, DateRange> {

    shared actual Date from;
    shared actual Date to;
    shared actual UnitOfDate step;

    shared actual Period period  {
        return from.periodTo(to);	
    }

    shared actual Duration duration  {
        return Duration((to.dayOfEra - from.dayOfEra) * milliseconds.perDay);	
    }

    shared actual Boolean equals( Object other ) {
        return Range::equals(other); 
    }

    shared actual DateRange? overlap(DateRange other) {
        assert( is DateRange? response = overlapUtil(this, other, step));
        return response;
    }

    shared actual DateRange? gap( DateRange other ) {
        assert( is DateRange? response = gapUtil(this, other, step) );
        return response;
    }

    "An iterator for the elements belonging to this 
     container. where each jump is based on actual step of this Range"
    shared actual Iterator<Date> iterator()  {
        object listIterator satisfies Iterator<Date> {
            variable Integer count = 0;
            shared actual Date|Finished next() {
                value date = from > to then previousByStep(from, step, count++) else nextByStep(from, step, count++);
                assert( is Date date );
                value continueLoop = from <= to then date <= to else date >= to;
                return continueLoop then date else finished;
            }
        }
        return listIterator;
    }
    
    "Define how this Range will get next or previous element while iterating."
    shared DateRange stepBy( UnitOfDate step ) {
        return step == this.step then this else DateRange(from, to, step);
    }

}