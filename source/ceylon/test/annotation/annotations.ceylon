import ceylon.language.meta.declaration {
    ...
}
import ceylon.test {
    ...
}
import ceylon.test.core {
    ...
}


"Annotation class for [[ceylon.test::test]]."
shared final annotation class TestAnnotation()
        satisfies OptionalAnnotation<TestAnnotation,FunctionDeclaration> {}


"Annotation class for [[ceylon.test::testSuite]]"
shared final annotation class TestSuiteAnnotation(
    "The program elements from which tests will be executed."
    shared {Declaration+} sources)
        satisfies OptionalAnnotation<TestSuiteAnnotation,FunctionDeclaration> {}


"Annotation class for [[ceylon.test::testExecutor]]."
shared final annotation class TestExecutorAnnotation(
    "The class declaration of [[ceylon.test::TestExecutor]]."
    shared ClassDeclaration executor)
        satisfies OptionalAnnotation<TestExecutorAnnotation,FunctionDeclaration|ClassDeclaration|Package|Module> {}


"Annotation class for [[ceylon.test::testListeners]]."
shared final annotation class TestListenersAnnotation(
    "The class declarations of [[ceylon.test::TestListener]]s"
    shared {ClassDeclaration+} listeners)
        satisfies OptionalAnnotation<TestListenersAnnotation,FunctionDeclaration|ClassDeclaration|Package|Module> {}


"Annotation class for [[ceylon.test::beforeTest]]."
shared final annotation class BeforeTestAnnotation()
        satisfies OptionalAnnotation<BeforeTestAnnotation,FunctionDeclaration> {}


"Annotation class for [[ceylon.test::afterTest]]."
shared final annotation class AfterTestAnnotation()
        satisfies OptionalAnnotation<AfterTestAnnotation,FunctionDeclaration> {}


"Annotation class for [[ceylon.test::ignore]]."
shared final annotation class IgnoreAnnotation(
    "Reason why the test is ignored."
    shared String reason)
        satisfies OptionalAnnotation<IgnoreAnnotation,FunctionDeclaration|ClassDeclaration|Package|Module> & TestCondition {
    
    shared actual Result evaluate(TestDescription description) => Result(false, reason);
    
}


"Annotation class for [[ceylon.test::tag]]."
shared final annotation class TagAnnotation(
    "One or more tags associated with the test."
    shared String+ tags)
        satisfies SequencedAnnotation<TagAnnotation,FunctionDeclaration|ClassDeclaration|Package|Module> {}


"Annotation class for [[ceylon.test::parameters]]."
shared final annotation class ParametersAnnotation(
    "The source function or value declaration."
    shared FunctionOrValueDeclaration source)
        satisfies OptionalAnnotation<ParametersAnnotation,FunctionOrValueDeclaration> & ArgumentListProvider & ArgumentProvider {
    
    shared actual {Anything*} arguments(ArgumentProviderContext context) {
        switch (source)
        case (is FunctionDeclaration) {
            return source.apply<{Anything*},[]>()();
        }
        case (is ValueDeclaration) {
            return source.apply<{Anything*}>().get();
        }
    }
    
    shared actual {Anything[]*} argumentLists(ArgumentProviderContext context) {
        value val = arguments(context);
        if( is Iterable<Anything[], Null> val) {
            return val;
        } else {
            return val.map((Anything e) => [e]); 
        }
    }
    
}